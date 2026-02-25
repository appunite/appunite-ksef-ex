defmodule KsefHub.InboundEmail.ReplyNotifier do
  @moduledoc """
  Builds and delivers reply emails for inbound email invoice processing.

  Follows the existing Swoosh notifier pattern (see `KsefHub.Accounts.UserNotifier`).
  """

  import Swoosh.Email

  alias KsefHub.Mailer

  @from_email Application.compile_env(
                :ksef_hub,
                :mailer_from,
                {"KSeF Hub", "noreply@ksef-hub.com"}
              )

  @doc "Builds a success reply email for a processed invoice."
  @spec success(String.t(), map(), keyword()) :: Swoosh.Email.t()
  def success(sender, invoice, opts \\ []) do
    invoice_number = Map.get(invoice, :invoice_number) || Map.get(invoice, "invoice_number")
    seller_name = Map.get(invoice, :seller_name) || Map.get(invoice, "seller_name") || ""
    invoice_id = Map.get(invoice, :id)

    subject =
      if invoice_number,
        do: "Invoice #{invoice_number} — added and ready",
        else: "Invoice added and ready"

    body = """

    ==============================

    Expense invoice #{invoice_number || "(no number)"}#{if seller_name != "", do: " from #{seller_name}", else: ""}
    has been added and is ready for review.

    #{invoice_url(invoice_id)}

    ==============================
    """

    build_email(sender, subject, body, opts)
  end

  @doc "Builds a needs-review reply email."
  @spec needs_review(String.t(), map(), keyword()) :: Swoosh.Email.t()
  def needs_review(sender, invoice, opts \\ []) do
    invoice_id = Map.get(invoice, :id)

    body = """

    ==============================

    Your invoice was uploaded but needs human review — some fields
    could not be extracted automatically.

    #{invoice_url(invoice_id)}

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

  @spec build_email(String.t(), String.t(), String.t(), keyword()) :: Swoosh.Email.t()
  defp build_email(sender, subject, body, opts) do
    email =
      new()
      |> to({sender, sender})
      |> from(@from_email)
      |> subject(subject)
      |> text_body(body)

    case Keyword.get(opts, :cc) do
      nil -> email
      cc_addr -> cc(email, {cc_addr, cc_addr})
    end
  end

  @doc "Delivers a reply email via the configured mailer."
  @spec deliver(Swoosh.Email.t()) :: {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver(email) do
    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @spec invoice_url(String.t() | nil) :: String.t()
  defp invoice_url(nil), do: ""

  defp invoice_url(id) do
    base_url = Application.get_env(:ksef_hub, KsefHubWeb.Endpoint)[:url][:host] || "ksef-hub.com"
    "https://#{base_url}/invoices/#{id}"
  end
end
