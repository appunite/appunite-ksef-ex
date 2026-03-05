defmodule KsefHub.InboundEmail.ReplyNotifier do
  @moduledoc """
  Builds and delivers reply emails for inbound email invoice processing.

  Follows the existing Swoosh notifier pattern (see `KsefHub.Accounts.UserNotifier`).
  """

  import Swoosh.Email

  require Logger

  alias KsefHub.Mailer

  @doc "Builds a success reply email for a processed invoice."
  @spec success(String.t(), KsefHub.Invoices.Invoice.t(), keyword()) :: Swoosh.Email.t()
  def success(sender, invoice, opts \\ []) do
    invoice_number = invoice.invoice_number
    seller_name = invoice.seller_name || ""

    subject =
      if invoice_number,
        do: "Invoice #{invoice_number} — added and ready",
        else: "Invoice added and ready"

    body = """

    ==============================

    Expense invoice #{invoice_number || "(no number)"}#{if seller_name != "", do: " from #{seller_name}", else: ""}
    has been added and is ready for review.

    #{invoice_url(invoice)}

    ==============================
    """

    build_email(sender, subject, body, opts)
  end

  @doc "Builds a needs-review reply email."
  @spec needs_review(String.t(), KsefHub.Invoices.Invoice.t(), keyword()) :: Swoosh.Email.t()
  def needs_review(sender, invoice, opts \\ []) do
    body = """

    ==============================

    Your invoice was uploaded but needs human review — some fields
    could not be extracted automatically.

    #{invoice_url(invoice)}

    ==============================
    """

    build_email(sender, "Invoice uploaded — needs human review", body, opts)
  end

  @doc "Builds a rejection reply email."
  @spec rejection(String.t(), atom(), keyword()) :: Swoosh.Email.t()
  def rejection(sender, reason, opts \\ [])

  def rejection(sender, :income_not_allowed, opts) do
    body = """

    ==============================

    This is an income invoice (seller NIP matches your company).
    Only expense invoices are accepted via email.

    ==============================
    """

    build_email(sender, "Invoice rejected — income invoice not accepted", body, opts)
  end

  def rejection(sender, :nip_mismatch, opts) do
    company_name = Keyword.get(opts, :company_name, "your company")
    nip = Keyword.get(opts, :nip, "")

    body = """

    ==============================

    Invoice rejected — buyer NIP doesn't match company #{company_name} (NIP: #{nip}).

    ==============================
    """

    build_email(sender, "Invoice rejected — NIP mismatch", body, opts)
  end

  def rejection(sender, :no_attachment, opts) do
    body = """

    ==============================

    No PDF attachment found. Please send exactly one PDF invoice per email.

    ==============================
    """

    build_email(sender, "Invoice rejected — no attachment", body, opts)
  end

  def rejection(sender, :multiple_attachments, opts) do
    body = """

    ==============================

    Multiple attachments detected. Please send exactly one PDF invoice per email.

    ==============================
    """

    build_email(sender, "Invoice rejected — multiple attachments", body, opts)
  end

  def rejection(sender, :non_pdf, opts) do
    filename = Keyword.get(opts, :filename, "attachment")

    body = """

    ==============================

    Attachment '#{filename}' is not a PDF. Only PDF files are supported.

    ==============================
    """

    build_email(sender, "Invoice rejected — not a PDF", body, opts)
  end

  @doc "Builds a NIP warning reply email — invoice was created but NIP verification flagged an issue."
  @spec nip_warning(String.t(), KsefHub.Invoices.Invoice.t(), atom(), keyword()) ::
          Swoosh.Email.t()
  def nip_warning(sender, invoice, reason, opts \\ []) do
    company_name = Keyword.get(opts, :company_name, "your company")
    nip = Keyword.get(opts, :nip, "")

    detail =
      case reason do
        :income_not_allowed ->
          "This appears to be an income invoice (seller NIP matches #{company_name})."

        :nip_mismatch ->
          "Buyer NIP doesn't match #{company_name} (NIP: #{nip})."

        _ ->
          "NIP verification flagged a potential issue."
      end

    body = """

    ==============================

    Your invoice was uploaded but flagged for review.
    #{detail}

    Please verify the invoice details:
    #{invoice_url(invoice)}

    ==============================
    """

    build_email(sender, "Invoice uploaded — needs review (NIP warning)", body, opts)
  end

  @doc "Builds an error reply email when invoice creation fails."
  @spec error(String.t(), term(), keyword()) :: Swoosh.Email.t()
  def error(sender, reason, opts \\ []) do
    detail = format_error_detail(reason)

    body = """

    ==============================

    Your invoice could not be processed due to a system error.
    #{detail}
    Please try uploading the invoice manually or contact support.

    ==============================
    """

    build_email(sender, "Invoice processing failed", body, opts)
  end

  @spec format_error_detail(term()) :: String.t()
  defp format_error_detail(%Ecto.Changeset{} = changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(safe_to_atom(key), key) |> to_string()
        end)
      end)

    "Details: #{inspect(errors)}"
  end

  defp format_error_detail(_reason), do: ""

  @spec safe_to_atom(String.t()) :: atom() | String.t()
  defp safe_to_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  @spec build_email(String.t(), String.t(), String.t(), keyword()) :: Swoosh.Email.t()
  defp build_email(sender, subject, body, opts) do
    reply_subject = threading_subject(subject, Keyword.get(opts, :original_subject))

    email =
      new()
      |> to({sender, sender})
      |> from(from_email())
      |> subject(reply_subject)
      |> text_body(body)

    email =
      case Keyword.get(opts, :cc) do
        nil -> email
        cc_addr -> cc(email, {cc_addr, cc_addr})
      end

    case Keyword.get(opts, :in_reply_to) do
      nil -> email
      message_id -> maybe_add_threading_headers(email, message_id)
    end
  end

  # Use "Re: <original_subject>" for threading when available.
  @spec threading_subject(String.t(), String.t() | nil) :: String.t()
  defp threading_subject(fallback, nil), do: fallback
  defp threading_subject(fallback, ""), do: fallback

  defp threading_subject(_fallback, original) do
    trimmed = String.trim_leading(original)

    if String.starts_with?(String.downcase(trimmed), "re:") do
      original
    else
      "Re: #{original}"
    end
  end

  @spec maybe_add_threading_headers(Swoosh.Email.t(), String.t()) :: Swoosh.Email.t()
  defp maybe_add_threading_headers(email, message_id) do
    normalized = normalize_message_id(message_id)

    if valid_message_id?(normalized) do
      email
      |> header("In-Reply-To", normalized)
      |> header("References", normalized)
    else
      Logger.warning("Skipping invalid Message-Id for threading: #{inspect(message_id)}")
      email
    end
  end

  # Ensure Message-Id is wrapped in angle brackets per RFC 5322.
  @spec normalize_message_id(String.t()) :: String.t()
  defp normalize_message_id(id) do
    trimmed = String.trim(id)

    if String.starts_with?(trimmed, "<") do
      trimmed
    else
      "<#{trimmed}>"
    end
  end

  # Validates Message-Id per RFC 5322: must be <non-empty-content>, no control chars.
  @spec valid_message_id?(String.t()) :: boolean()
  defp valid_message_id?(id) when is_binary(id) do
    Regex.match?(~r/^<[^>]+>$/, id) and
      not String.contains?(id, ["\r", "\n", "\0"])
  end

  defp valid_message_id?(_), do: false

  @doc "Delivers a reply email via the configured mailer."
  @spec deliver(Swoosh.Email.t()) :: {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver(email) do
    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @spec from_email() :: {String.t(), String.t()}
  defp from_email do
    case Application.get_env(:ksef_hub, :inbound_email_domain) do
      domain when is_binary(domain) ->
        trimmed = String.trim(domain)

        if trimmed != "" and Regex.match?(~r/^[a-zA-Z0-9.\-]+$/, trimmed) do
          {"Invoi", "noreply@#{trimmed}"}
        else
          default_from()
        end

      _ ->
        default_from()
    end
  end

  @spec default_from() :: {String.t(), String.t()}
  defp default_from do
    Application.get_env(:ksef_hub, :mailer_from, {"Invoi", "noreply@ksef-hub.com"})
  end

  @spec invoice_url(KsefHub.Invoices.Invoice.t() | nil) :: String.t()
  defp invoice_url(nil), do: ""

  defp invoice_url(invoice) do
    "#{KsefHubWeb.Endpoint.url()}/c/#{invoice.company_id}/invoices/#{invoice.id}"
  end
end
