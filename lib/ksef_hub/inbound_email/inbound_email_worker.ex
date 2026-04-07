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
  alias KsefHub.InboundEmail.{CcParser, EmailReplyWorker, NipVerifier, ReplyNotifier}
  alias KsefHub.InvoiceClassifier.Worker, as: ClassifierWorker
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
    nip_result = NipVerifier.verify_expense(extracted, company.nip)

    case {extraction_status, nip_result} do
      {:complete, {:ok, :expense}} ->
        create_and_notify(record, company, extracted, :success)

      {_, {:error, reason}} ->
        reject_and_notify(record, company, reason)

      _ ->
        create_and_notify(record, company, extracted, :needs_review)
    end
  end

  @spec reject_and_notify(InboundEmail.InboundEmail.t(), Companies.Company.t(), atom()) :: :ok
  defp reject_and_notify(record, company, reason) do
    error_message =
      case reason do
        :income_not_allowed -> "Rejected: income invoice not accepted via email"
        :nip_mismatch -> "Rejected: buyer NIP doesn't match company"
        _ -> "Rejected: NIP verification failed"
      end

    log_status_update(
      InboundEmail.update_status(record, %{status: :failed, error_message: error_message}),
      record.id
    )

    opts =
      reply_opts(company, record)
      |> Keyword.merge(company_name: company.name, nip: company.nip)

    send_reply(ReplyNotifier.rejection(record.sender, reason, opts), record)
    :ok
  end

  @type reply_type :: :success | :needs_review

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
    create_opts = [
      filename: record.original_filename,
      sender_email: record.sender,
      skip_prediction: true
    ]

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

    reply_args = reply_worker_args(record, company, invoice, reply_type)
    enqueue_classification_chain(invoice, reply_type, reply_args)
    :ok
  end

  # If creation with extracted data fails, retry with :extraction_failed to store just the PDF.
  @spec fallback_create_and_notify(
          InboundEmail.InboundEmail.t(),
          Companies.Company.t(),
          term(),
          reply_type()
        ) :: :ok
  defp fallback_create_and_notify(record, company, original_reason, reply_type) do
    create_opts = [
      filename: record.original_filename,
      sender_email: record.sender,
      skip_prediction: true
    ]

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

        fallback_type = fallback_reply_type(reply_type)
        reply_args = reply_worker_args(record, company, invoice, fallback_type)
        # No classification for failed extraction — send reply directly
        enqueue_reply(reply_args)
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

  # When fallback creates an invoice with :extraction_failed,
  # downgrade :success to :needs_review since extraction data was lost.
  @spec fallback_reply_type(reply_type()) :: reply_type()
  defp fallback_reply_type(:success), do: :needs_review
  defp fallback_reply_type(other), do: other

  @spec reply_worker_args(
          InboundEmail.InboundEmail.t(),
          Companies.Company.t(),
          Invoices.Invoice.t(),
          reply_type()
        ) :: map()
  defp reply_worker_args(record, company, invoice, reply_type) do
    %{
      inbound_email_id: record.id,
      company_id: company.id,
      invoice_id: invoice.id,
      reply_type: Atom.to_string(reply_type)
    }
  end

  # For complete extraction: chain ClassifierWorker → EmailReplyWorker.
  # For partial/failed extraction: send reply directly (no classification).
  @spec enqueue_classification_chain(Invoices.Invoice.t(), reply_type(), map()) :: :ok
  defp enqueue_classification_chain(invoice, :success, reply_args) do
    on_complete = %{
      worker: "KsefHub.InboundEmail.EmailReplyWorker",
      args: reply_args
    }

    case ClassifierWorker.maybe_enqueue(invoice, on_complete: on_complete) do
      {:ok, _job} ->
        :ok

      :skip ->
        # Non-expense or other skip — send reply without classification
        enqueue_reply(reply_args)

      {:error, reason} ->
        Logger.warning(
          "Failed to enqueue classifier for invoice #{invoice.id}: #{inspect(reason)}, sending reply directly"
        )

        enqueue_reply(reply_args)
    end
  end

  defp enqueue_classification_chain(_invoice, _reply_type, reply_args) do
    enqueue_reply(reply_args)
  end

  @spec enqueue_reply(map()) :: :ok
  defp enqueue_reply(reply_args) do
    case reply_args |> EmailReplyWorker.new() |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Failed to enqueue email reply for inbound email #{reply_args.inbound_email_id}: #{inspect(reason)}"
        )

        :ok
    end
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
    cc_opts =
      case CcParser.build_cc_list(record.original_cc, company.inbound_cc_email, [
             record.sender,
             record.recipient
           ]) do
        [] -> []
        cc_list -> [cc: cc_list]
      end

    cc_opts
    |> maybe_add(:in_reply_to, record.mailgun_message_id)
    |> maybe_add(:original_subject, record.subject)
  end

  @spec maybe_add(keyword(), atom(), String.t() | nil) :: keyword()
  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, _key, ""), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

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
