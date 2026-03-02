defmodule KsefHubWeb.WebhookController do
  @moduledoc """
  Handles Mailgun inbound email webhooks for invoice processing.

  Verifies HMAC-SHA256 signature, validates sender domain, parses
  company token from recipient address, validates attachments,
  and enqueues async processing via Oban.
  """

  use KsefHubWeb, :controller

  require Logger

  alias KsefHub.Companies
  alias KsefHub.InboundEmail
  alias KsefHub.InboundEmail.{InboundEmailWorker, ReplyNotifier, SignatureVerifier}

  @doc "Processes a Mailgun inbound email webhook."
  @spec inbound(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def inbound(conn, params) do
    with :ok <- verify_signature(params),
         {:ok, sender} <- parse_sender(params),
         {:ok, token} <- parse_company_token(params),
         {:ok, company} <- lookup_company(token),
         :ok <- validate_sender_domain(sender, company),
         {:ok, attachment} <- validate_attachments(params, sender, company) do
      process_inbound(conn, company, sender, params, attachment)
    else
      {:error, :invalid_signature} ->
        conn
        |> put_status(406)
        |> json(%{error: "Invalid signature"})

      {:error, :disallowed_domain} ->
        json(conn, %{status: "discarded"})

      {:error, :invalid_sender} ->
        json(conn, %{status: "discarded"})

      {:error, :unknown_company} ->
        json(conn, %{status: "rejected", reason: "Unknown company token"})

      {:error, {:attachment_error, reason, sender, company}} ->
        send_attachment_error_reply(sender, reason, company, params)
        json(conn, %{status: "rejected", reason: attachment_error_message(reason)})
    end
  end

  @spec verify_signature(map()) :: :ok | {:error, :invalid_signature}
  defp verify_signature(params) do
    case Application.get_env(:ksef_hub, :mailgun_signing_key) do
      nil ->
        Logger.error("Mailgun signing key not configured — rejecting webhook")
        {:error, :invalid_signature}

      signing_key ->
        SignatureVerifier.verify(
          params["timestamp"],
          params["token"],
          params["signature"],
          signing_key
        )
    end
  end

  @spec parse_sender(map()) :: {:ok, String.t()} | {:error, :invalid_sender}
  defp parse_sender(params) do
    sender = params["sender"] || ""

    case String.split(sender, "@") do
      [local, domain] when local != "" and domain != "" ->
        {:ok, sender}

      _ ->
        Logger.info("Invalid sender address format received")
        {:error, :invalid_sender}
    end
  end

  @spec validate_sender_domain(String.t(), Companies.Company.t()) ::
          :ok | {:error, :disallowed_domain}
  defp validate_sender_domain(_sender, %{inbound_allowed_sender_domain: nil}), do: :ok
  defp validate_sender_domain(_sender, %{inbound_allowed_sender_domain: ""}), do: :ok

  defp validate_sender_domain(sender, %{inbound_allowed_sender_domain: allowed}) do
    # sender is guaranteed to contain exactly one "@" by parse_sender/1
    domain = sender |> String.split("@") |> List.last()

    if String.downcase(domain) == String.downcase(allowed) do
      :ok
    else
      Logger.info("Discarding inbound email from disallowed domain: #{domain}")
      {:error, :disallowed_domain}
    end
  end

  @spec parse_company_token(map()) :: {:ok, String.t()} | {:error, :unknown_company}
  defp parse_company_token(params) do
    recipient = params["recipient"] || ""

    case Regex.run(~r/^inv-([a-z0-9]+)@/, recipient) do
      [_, token] -> {:ok, token}
      _ -> {:error, :unknown_company}
    end
  end

  @spec lookup_company(String.t()) ::
          {:ok, Companies.Company.t()} | {:error, :unknown_company}
  defp lookup_company(token) do
    case Companies.get_company_by_inbound_email_token(token) do
      nil -> {:error, :unknown_company}
      company -> {:ok, company}
    end
  end

  @spec validate_attachments(map(), String.t(), Companies.Company.t()) ::
          {:ok, Plug.Upload.t()}
          | {:error, {:attachment_error, term(), String.t(), Companies.Company.t()}}
  defp validate_attachments(params, sender, company) do
    attachments = collect_attachments(params)

    case attachments do
      [] ->
        {:error, {:attachment_error, :no_attachment, sender, company}}

      [single] ->
        if pdf_attachment?(single) do
          {:ok, single}
        else
          {:error, {:attachment_error, {:non_pdf, single.filename}, sender, company}}
        end

      _multiple ->
        {:error, {:attachment_error, :multiple_attachments, sender, company}}
    end
  end

  @spec collect_attachments(map()) :: [Plug.Upload.t()]
  defp collect_attachments(params) do
    params
    |> Enum.filter(fn {key, value} ->
      String.starts_with?(key, "attachment-") and match?(%Plug.Upload{}, value)
    end)
    |> Enum.map(fn {_key, upload} -> upload end)
  end

  # Best-effort pre-check; definitive PDF validation happens during extraction.
  @spec pdf_attachment?(Plug.Upload.t()) :: boolean()
  defp pdf_attachment?(%Plug.Upload{content_type: ct, filename: filename}) do
    if ct in [nil, ""] do
      String.downcase(filename || "") |> String.ends_with?(".pdf")
    else
      ct == "application/pdf"
    end
  end

  @spec process_inbound(
          Plug.Conn.t(),
          Companies.Company.t(),
          String.t(),
          map(),
          Plug.Upload.t()
        ) :: Plug.Conn.t()
  defp process_inbound(conn, company, sender, params, attachment) do
    case File.read(attachment.path) do
      {:ok, pdf_binary} ->
        create_and_enqueue(conn, company, sender, params, pdf_binary, attachment.filename)

      {:error, reason} ->
        Logger.error("Failed to read attachment #{attachment.path}: #{inspect(reason)}")
        json(conn, %{status: "error", reason: "Failed to read attachment"})
    end
  end

  @spec create_and_enqueue(
          Plug.Conn.t(),
          Companies.Company.t(),
          String.t(),
          map(),
          binary(),
          String.t() | nil
        ) :: Plug.Conn.t()
  defp create_and_enqueue(conn, company, sender, params, pdf_binary, filename) do
    case InboundEmail.create_inbound_email(company.id, %{
           sender: sender,
           recipient: params["recipient"] || "",
           subject: params["subject"],
           status: :received,
           mailgun_message_id: params["Message-Id"],
           pdf_content: pdf_binary,
           original_filename: filename
         }) do
      {:ok, record} ->
        case enqueue_processing(record, company) do
          {:ok, _job} ->
            json(conn, %{status: "ok"})

          {:error, reason} ->
            Logger.error("Failed to enqueue processing for #{record.id}: #{inspect(reason)}")

            InboundEmail.update_status(record, %{
              status: :failed,
              error_message: "enqueue failed: #{inspect(reason)}"
            })

            json(conn, %{status: "error", reason: "Failed to enqueue processing"})
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        if duplicate_message_id?(changeset) do
          json(conn, %{status: "ok"})
        else
          Logger.error("Failed to create inbound email: #{inspect(changeset.errors)}")
          json(conn, %{status: "error", reason: "Failed to process email"})
        end
    end
  end

  @spec duplicate_message_id?(Ecto.Changeset.t()) :: boolean()
  defp duplicate_message_id?(changeset) do
    Enum.any?(changeset.errors, fn
      {:mailgun_message_id, {_, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  @spec enqueue_processing(InboundEmail.InboundEmail.t(), Companies.Company.t()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  defp enqueue_processing(record, company) do
    %{inbound_email_id: record.id, company_id: company.id}
    |> InboundEmailWorker.new()
    |> Oban.insert()
  end

  @spec send_attachment_error_reply(String.t(), atom() | tuple(), Companies.Company.t(), map()) ::
          :ok
  defp send_attachment_error_reply(sender, reason, company, params) do
    opts = cc_opts(company) ++ in_reply_to_opts(params)
    {rejection_reason, extra_opts} = normalize_attachment_error(reason)

    email = ReplyNotifier.rejection(sender, rejection_reason, opts ++ extra_opts)

    case ReplyNotifier.deliver(email) do
      {:ok, _} ->
        :ok

      {:error, delivery_err} ->
        Logger.warning("Failed to send rejection reply: #{inspect(delivery_err)}")
    end
  end

  @spec cc_opts(Companies.Company.t()) :: keyword()
  defp cc_opts(%{inbound_cc_email: nil}), do: []
  defp cc_opts(%{inbound_cc_email: ""}), do: []
  defp cc_opts(%{inbound_cc_email: cc}), do: [cc: cc]

  @spec in_reply_to_opts(map()) :: keyword()
  defp in_reply_to_opts(%{"Message-Id" => msg_id}) when is_binary(msg_id),
    do: [in_reply_to: msg_id]

  defp in_reply_to_opts(_), do: []

  @spec normalize_attachment_error(atom() | tuple()) :: {atom(), keyword()}
  defp normalize_attachment_error(:no_attachment), do: {:no_attachment, []}
  defp normalize_attachment_error(:multiple_attachments), do: {:multiple_attachments, []}

  defp normalize_attachment_error({:non_pdf, filename}),
    do: {:non_pdf, [filename: filename]}

  @spec attachment_error_message(atom() | tuple()) :: String.t()
  defp attachment_error_message(:no_attachment), do: "No PDF attachment found"
  defp attachment_error_message(:multiple_attachments), do: "Multiple attachments detected"
  defp attachment_error_message({:non_pdf, _}), do: "Attachment is not a PDF"
end
