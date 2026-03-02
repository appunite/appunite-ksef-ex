defmodule KsefHub.InboundEmail.InboundEmailWorker do
  @moduledoc """
  Oban worker that processes inbound email PDF attachments.

  Extracts invoice data from the PDF, verifies NIP ownership (expense-only),
  creates the invoice record, and sends a reply email to the sender.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias KsefHub.Companies
  alias KsefHub.InboundEmail
  alias KsefHub.InboundEmail.{NipVerifier, ReplyNotifier}
  alias KsefHub.InvoiceExtractor.ContextBuilder
  alias KsefHub.Invoices

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:cancel, String.t()} | {:error, term()}
  def perform(%Oban.Job{
        args: %{"inbound_email_id" => inbound_email_id, "company_id" => company_id}
      }) do
    with {:record, %{} = record} <- {:record, InboundEmail.get_inbound_email(inbound_email_id)},
         {:company, %{} = company} <- {:company, Companies.get_company(company_id)},
         {:ok, record} <- InboundEmail.update_status(record, %{status: :processing}) do
      process_email(record, company)
    else
      {:record, nil} ->
        {:cancel, "inbound email not found"}

      {:company, nil} ->
        {:cancel, "company not found"}

      {:error, reason} ->
        Logger.error(
          "Failed to set processing status for #{inbound_email_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @spec process_email(InboundEmail.InboundEmail.t(), Companies.Company.t()) :: :ok
  defp process_email(record, company) do
    case extract_pdf(record, company) do
      {:ok, extracted} -> handle_extraction(record, company, extracted)
      {:error, _reason} -> create_and_notify(record, company, :extraction_failed, :needs_review)
    end
  end

  @spec extract_pdf(InboundEmail.InboundEmail.t(), Companies.Company.t()) ::
          {:ok, map()} | {:error, term()}
  defp extract_pdf(%{pdf_file: nil}, _company), do: {:error, :no_pdf_file}

  defp extract_pdf(record, company) do
    context = ContextBuilder.build(company)

    invoice_extractor().extract(record.pdf_file.content,
      filename: record.original_filename || "invoice.pdf",
      context: context
    )
  end

  @spec handle_extraction(InboundEmail.InboundEmail.t(), Companies.Company.t(), map()) :: :ok
  defp handle_extraction(record, company, extracted) do
    extraction_status = Invoices.determine_extraction_status_from_attrs(extracted)

    case {extraction_status, NipVerifier.verify_expense(extracted, company.nip)} do
      {:complete, {:ok, :expense}} ->
        create_and_notify(record, company, extracted, :success)

      {_, {:error, reason}} ->
        create_and_notify(record, company, extracted, {:nip_warning, reason})

      {:partial, {:ok, :expense}} ->
        create_and_notify(record, company, extracted, :needs_review)

      {_, {:undetermined, :needs_review}} ->
        create_and_notify(record, company, extracted, :needs_review)

      {_status, _nip_result} ->
        create_and_notify(record, company, extracted, :needs_review)
    end
  end

  @type reply_type :: :success | :needs_review | {:nip_warning, atom()}

  @spec create_and_notify(
          InboundEmail.InboundEmail.t(),
          Companies.Company.t(),
          map() | :extraction_failed,
          reply_type()
        ) :: :ok
  defp create_and_notify(%{pdf_file: nil} = record, company, _extracted, _reply_type) do
    Logger.error("No PDF file for inbound email #{record.id}")

    log_status_update(
      InboundEmail.update_status(record, %{status: :failed, error_message: "no PDF file"}),
      record.id
    )

    opts = reply_opts(company, record)
    send_reply(ReplyNotifier.error(record.sender, :no_pdf_file, opts), record)
    :ok
  end

  defp create_and_notify(record, company, extracted, reply_type) do
    create_opts = [filename: record.original_filename]

    case Invoices.create_email_invoice(
           company.id,
           record.pdf_file.content,
           extracted,
           create_opts
         ) do
      {:ok, invoice} ->
        complete_and_notify(record, company, invoice, reply_type)

      {:error, reason} ->
        Logger.error("Failed to create email invoice: #{inspect(reason)}, retrying as failed")
        fallback_create_and_notify(record, company, reason, reply_type)
    end
  end

  @spec complete_and_notify(
          InboundEmail.InboundEmail.t(),
          Companies.Company.t(),
          Invoices.Invoice.t(),
          reply_type()
        ) :: :ok
  defp complete_and_notify(record, company, invoice, reply_type) do
    log_status_update(
      InboundEmail.update_status(record, %{status: :completed, invoice_id: invoice.id}),
      record.id
    )

    opts = reply_opts(company, record)
    send_reply(build_reply(reply_type, record.sender, invoice, company, opts), record)
    :ok
  end

  # If creation with extracted data fails, retry with :extraction_failed to store just the PDF.
  @spec fallback_create_and_notify(
          InboundEmail.InboundEmail.t(),
          Companies.Company.t(),
          term(),
          reply_type()
        ) :: :ok
  defp fallback_create_and_notify(record, company, original_reason, _reply_type) do
    create_opts = [filename: record.original_filename]

    case Invoices.create_email_invoice(
           company.id,
           record.pdf_file.content,
           :extraction_failed,
           create_opts
         ) do
      {:ok, invoice} ->
        log_status_update(
          InboundEmail.update_status(record, %{status: :completed, invoice_id: invoice.id}),
          record.id
        )

        opts = reply_opts(company, record)
        send_reply(ReplyNotifier.needs_review(record.sender, invoice, opts), record)
        :ok

      {:error, fallback_reason} ->
        Logger.error("Fallback invoice creation also failed: #{inspect(fallback_reason)}")

        log_status_update(
          InboundEmail.update_status(record, %{
            status: :failed,
            error_message: inspect(original_reason)
          }),
          record.id
        )

        opts = reply_opts(company, record)
        send_reply(ReplyNotifier.error(record.sender, original_reason, opts), record)
        :ok
    end
  end

  @spec build_reply(
          reply_type(),
          String.t(),
          Invoices.Invoice.t(),
          Companies.Company.t(),
          keyword()
        ) ::
          Swoosh.Email.t()
  defp build_reply(:success, sender, invoice, _company, opts),
    do: ReplyNotifier.success(sender, invoice, opts)

  defp build_reply(:needs_review, sender, invoice, _company, opts),
    do: ReplyNotifier.needs_review(sender, invoice, opts)

  defp build_reply({:nip_warning, reason}, sender, invoice, company, opts) do
    opts = Keyword.merge(opts, company_name: company.name, nip: company.nip)
    ReplyNotifier.nip_warning(sender, invoice, reason, opts)
  end

  @spec send_reply(Swoosh.Email.t(), InboundEmail.InboundEmail.t()) :: :ok
  defp send_reply(email, record) do
    case ReplyNotifier.deliver(email) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to send reply for inbound email #{record.id}: #{inspect(reason)}")
        :ok
    end
  end

  @spec reply_opts(Companies.Company.t(), InboundEmail.InboundEmail.t()) :: keyword()
  defp reply_opts(company, record) do
    opts =
      case company.inbound_cc_email do
        nil -> []
        "" -> []
        cc -> [cc: cc]
      end

    opts =
      case record.mailgun_message_id do
        nil -> opts
        msg_id -> Keyword.put(opts, :in_reply_to, msg_id)
      end

    case record.subject do
      nil -> opts
      "" -> opts
      subject -> Keyword.put(opts, :original_subject, subject)
    end
  end

  @spec log_status_update({:ok, term()} | {:error, term()}, String.t()) :: :ok
  defp log_status_update({:ok, _}, _id), do: :ok

  defp log_status_update({:error, reason}, id) do
    Logger.error("Failed to update inbound email #{id} status: #{inspect(reason)}")
    :ok
  end

  @spec invoice_extractor() :: module()
  defp invoice_extractor do
    Application.get_env(:ksef_hub, :invoice_extractor, KsefHub.InvoiceExtractor.Client)
  end
end
