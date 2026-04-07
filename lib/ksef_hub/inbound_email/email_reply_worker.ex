defmodule KsefHub.InboundEmail.EmailReplyWorker do
  @moduledoc """
  Oban worker that sends reply emails with full invoice details.

  Chained from `ClassifierWorker` via `on_complete` args, so it runs after
  classification finishes. Preloads the category association to include
  the applied category name and emoji in the reply.

  Can also be enqueued directly for cases where classification is skipped
  (e.g. extraction failed, partial extraction).
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias KsefHub.Companies
  alias KsefHub.InboundEmail
  alias KsefHub.InboundEmail.{CcParser, ReplyNotifier}
  alias KsefHub.Invoices
  alias KsefHub.Repo

  @doc "Sends the reply email for a processed inbound email invoice. Preloads category for rich details."
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:cancel, String.t()}
  def perform(%Oban.Job{
        args: %{
          "inbound_email_id" => inbound_email_id,
          "company_id" => company_id,
          "invoice_id" => invoice_id,
          "reply_type" => reply_type
        }
      }) do
    with {:record, %{} = record} <- {:record, InboundEmail.get_inbound_email(inbound_email_id)},
         {:company, %{} = company} <- {:company, Companies.get_company(company_id)},
         {:invoice, %{} = invoice} <- {:invoice, Invoices.get_invoice(company_id, invoice_id)} do
      invoice = Repo.preload(invoice, :category)
      send_reply(record, company, invoice, String.to_existing_atom(reply_type))
      :ok
    else
      {:record, nil} -> {:cancel, "inbound email not found"}
      {:company, nil} -> {:cancel, "company not found"}
      {:invoice, nil} -> {:cancel, "invoice not found"}
    end
  end

  @spec send_reply(
          InboundEmail.InboundEmail.t(),
          Companies.Company.t(),
          Invoices.Invoice.t(),
          :success | :needs_review
        ) :: :ok
  defp send_reply(record, company, invoice, reply_type) do
    opts = reply_opts(company, record)
    email = build_reply(reply_type, record.sender, invoice, opts)

    case ReplyNotifier.deliver(email) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to send reply for inbound email #{record.id}: #{inspect(reason)}")
        :ok
    end
  end

  @spec build_reply(:success | :needs_review, String.t(), Invoices.Invoice.t(), keyword()) ::
          Swoosh.Email.t()
  defp build_reply(:success, sender, invoice, opts),
    do: ReplyNotifier.success(sender, invoice, opts)

  defp build_reply(:needs_review, sender, invoice, opts),
    do: ReplyNotifier.needs_review(sender, invoice, opts)

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
end
