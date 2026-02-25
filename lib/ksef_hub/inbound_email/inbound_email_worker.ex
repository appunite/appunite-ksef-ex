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
  alias KsefHub.Invoices

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:cancel, String.t()} | {:error, term()}
  def perform(%Oban.Job{
        args: %{"inbound_email_id" => inbound_email_id, "company_id" => company_id}
      }) do
    with {:record, %{} = record} <- {:record, InboundEmail.get_inbound_email(inbound_email_id)},
         {:company, %{} = company} <- {:company, Companies.get_company(company_id)} do
      InboundEmail.update_status(record, %{status: :processing})
      process_email(record, company)
    else
      {:record, nil} -> {:cancel, "inbound email not found"}
      {:company, nil} -> {:cancel, "company not found"}
    end
  end

  @spec process_email(InboundEmail.InboundEmail.t(), Companies.Company.t()) ::
          :ok | {:error, term()}
  defp process_email(record, company) do
    case extract_pdf(record) do
      {:ok, extracted} ->
        handle_extraction_success(record, company, extracted)

      {:error, _reason} ->
        handle_extraction_failure(record, company)
    end
  end

  @spec extract_pdf(InboundEmail.InboundEmail.t()) :: {:ok, map()} | {:error, term()}
  defp extract_pdf(record) do
    unstructured_client().extract(record.pdf_content,
      filename: record.original_filename || "invoice.pdf"
    )
  end

  @spec handle_extraction_success(
          InboundEmail.InboundEmail.t(),
          Companies.Company.t(),
          map()
        ) :: :ok
  defp handle_extraction_success(record, company, extracted) do
    extraction_status = Invoices.determine_extraction_status_from_attrs(extracted)

    case {extraction_status, NipVerifier.verify_expense(extracted, company.nip)} do
      {:complete, {:ok, :expense}} ->
        create_and_notify_success(record, company, extracted)

      {:complete, {:error, reason}} ->
        reject_and_notify(record, company, reason)

      {_partial_or_failed, {:error, reason}} ->
        reject_and_notify(record, company, reason)

      {_partial, {:undetermined, :needs_review}} ->
        create_and_notify_needs_review(record, company, extracted)

      {:complete, {:undetermined, :needs_review}} ->
        create_and_notify_needs_review(record, company, extracted)
    end
  end

  @spec handle_extraction_failure(InboundEmail.InboundEmail.t(), Companies.Company.t()) :: :ok
  defp handle_extraction_failure(record, company) do
    case Invoices.create_email_invoice(company.id, record.pdf_content, :extraction_failed,
           filename: record.original_filename
         ) do
      {:ok, invoice} ->
        InboundEmail.update_status(record, %{status: :completed, invoice_id: invoice.id})
        send_reply(ReplyNotifier.needs_review(record.sender, invoice, reply_opts()), record)
        :ok

      {:error, reason} ->
        Logger.error("Failed to create email invoice: #{inspect(reason)}")
        InboundEmail.update_status(record, %{status: :failed, error_message: inspect(reason)})
        :ok
    end
  end

  @spec create_and_notify_success(
          InboundEmail.InboundEmail.t(),
          Companies.Company.t(),
          map()
        ) :: :ok
  defp create_and_notify_success(record, company, extracted) do
    case Invoices.create_email_invoice(company.id, record.pdf_content, extracted,
           filename: record.original_filename
         ) do
      {:ok, invoice} ->
        InboundEmail.update_status(record, %{status: :completed, invoice_id: invoice.id})
        send_reply(ReplyNotifier.success(record.sender, invoice, reply_opts()), record)
        :ok

      {:error, reason} ->
        Logger.error("Failed to create email invoice: #{inspect(reason)}")
        InboundEmail.update_status(record, %{status: :failed, error_message: inspect(reason)})
        :ok
    end
  end

  @spec create_and_notify_needs_review(
          InboundEmail.InboundEmail.t(),
          Companies.Company.t(),
          map()
        ) :: :ok
  defp create_and_notify_needs_review(record, company, extracted) do
    case Invoices.create_email_invoice(company.id, record.pdf_content, extracted,
           filename: record.original_filename
         ) do
      {:ok, invoice} ->
        InboundEmail.update_status(record, %{status: :completed, invoice_id: invoice.id})
        send_reply(ReplyNotifier.needs_review(record.sender, invoice, reply_opts()), record)
        :ok

      {:error, reason} ->
        Logger.error("Failed to create email invoice: #{inspect(reason)}")
        InboundEmail.update_status(record, %{status: :failed, error_message: inspect(reason)})
        :ok
    end
  end

  @spec reject_and_notify(InboundEmail.InboundEmail.t(), Companies.Company.t(), atom()) :: :ok
  defp reject_and_notify(record, company, reason) do
    error_msg = rejection_message(reason)
    InboundEmail.update_status(record, %{status: :rejected, error_message: error_msg})

    opts = Keyword.merge(reply_opts(), company_name: company.name, nip: company.nip)
    send_reply(ReplyNotifier.rejection(record.sender, reason, opts), record)
    :ok
  end

  @spec send_reply(Swoosh.Email.t(), InboundEmail.InboundEmail.t()) :: :ok
  defp send_reply(email, record) do
    case ReplyNotifier.deliver(email) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Failed to send reply for inbound email #{record.id}: #{inspect(reason)}"
        )

        :ok
    end
  end

  @spec reply_opts() :: keyword()
  defp reply_opts do
    case Application.get_env(:ksef_hub, :inbound_cc_email) do
      nil -> []
      cc -> [cc: cc]
    end
  end

  @spec rejection_message(atom()) :: String.t()
  defp rejection_message(:income_not_allowed),
    do: "Income invoice — seller NIP matches company"

  defp rejection_message(:nip_mismatch),
    do: "Buyer NIP doesn't match company"

  @spec unstructured_client() :: module()
  defp unstructured_client do
    Application.get_env(:ksef_hub, :unstructured_client, KsefHub.Unstructured.Client)
  end
end
