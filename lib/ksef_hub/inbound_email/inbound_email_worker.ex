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
  alias KsefHub.Unstructured.ContextBuilder

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
  defp extract_pdf(record, company) do
    context = ContextBuilder.build(company)

    unstructured_client().extract(record.pdf_content,
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
        reject_and_notify(record, company, reason)

      {:partial, {:ok, :expense}} ->
        create_and_notify(record, company, extracted, :needs_review)

      {_, {:undetermined, :needs_review}} ->
        create_and_notify(record, company, extracted, :needs_review)

      {status, nip_result} ->
        Logger.warning("Unexpected extraction/NIP combination: #{inspect({status, nip_result})}")
        create_and_notify(record, company, extracted, :needs_review)
    end
  end

  @spec create_and_notify(
          InboundEmail.InboundEmail.t(),
          Companies.Company.t(),
          map() | :extraction_failed,
          :success | :needs_review
        ) :: :ok
  defp create_and_notify(record, company, extracted, reply_type) do
    case Invoices.create_email_invoice(company.id, record.pdf_content, extracted,
           filename: record.original_filename
         ) do
      {:ok, invoice} ->
        log_status_update(
          InboundEmail.update_status(record, %{status: :completed, invoice_id: invoice.id}),
          record.id
        )

        send_reply(build_reply(reply_type, record.sender, invoice), record)
        :ok

      {:error, reason} ->
        Logger.error("Failed to create email invoice: #{inspect(reason)}")

        log_status_update(
          InboundEmail.update_status(record, %{status: :failed, error_message: inspect(reason)}),
          record.id
        )

        :ok
    end
  end

  @spec build_reply(:success | :needs_review, String.t(), Invoices.Invoice.t()) ::
          Swoosh.Email.t()
  defp build_reply(:success, sender, invoice),
    do: ReplyNotifier.success(sender, invoice, reply_opts())

  defp build_reply(:needs_review, sender, invoice),
    do: ReplyNotifier.needs_review(sender, invoice, reply_opts())

  @spec reject_and_notify(InboundEmail.InboundEmail.t(), Companies.Company.t(), atom()) :: :ok
  defp reject_and_notify(record, company, reason) do
    log_status_update(
      InboundEmail.update_status(record, %{
        status: :rejected,
        error_message: rejection_message(reason)
      }),
      record.id
    )

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
        Logger.warning("Failed to send reply for inbound email #{record.id}: #{inspect(reason)}")
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

  @spec log_status_update({:ok, term()} | {:error, term()}, String.t()) :: :ok
  defp log_status_update({:ok, _}, _id), do: :ok

  defp log_status_update({:error, reason}, id) do
    Logger.error("Failed to update inbound email #{id} status: #{inspect(reason)}")
    :ok
  end

  @spec unstructured_client() :: module()
  defp unstructured_client do
    Application.get_env(:ksef_hub, :unstructured_client, KsefHub.Unstructured.Client)
  end
end
