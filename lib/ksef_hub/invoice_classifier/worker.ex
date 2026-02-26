defmodule KsefHub.InvoiceClassifier.Worker do
  @moduledoc """
  Oban worker that runs ML classification for newly created expense invoices.

  Enqueued after invoice creation (sync or manual). Skips income invoices,
  already-manual predictions, and missing invoices. Cancels permanently on
  configuration errors (won't help to retry).
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias KsefHub.InvoiceClassifier
  alias KsefHub.Invoices

  @doc """
  Conditionally enqueues a classification job for an expense invoice.

  Returns `{:ok, %Oban.Job{}}` for expense invoices, `{:error, changeset}`
  on Oban insert failure, or `:skip` for non-expense invoices.
  """
  @spec maybe_enqueue(Invoices.Invoice.t()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | :skip
  def maybe_enqueue(%{type: :expense, id: id, company_id: company_id}) do
    %{invoice_id: id, company_id: company_id}
    |> new()
    |> Oban.insert()
  end

  def maybe_enqueue(_invoice), do: :skip

  @doc """
  Oban entry point: classifies an expense invoice via the ML sidecar.

  Looks up the invoice by `"invoice_id"` and `"company_id"` from job args.
  Returns `:ok` on success, `{:cancel, reason}` for non-retryable cases
  (missing invoice, non-expense, already manual, service not configured),
  or `{:error, term()}` for transient failures.
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:cancel, String.t()} | {:error, term()}
  def perform(%Oban.Job{args: %{"invoice_id" => invoice_id, "company_id" => company_id}}) do
    case Invoices.get_invoice(company_id, invoice_id) do
      nil ->
        {:cancel, "invoice not found"}

      %{prediction_status: :manual} ->
        {:cancel, "already manually classified"}

      %{type: :expense} = invoice ->
        run_classification(invoice)

      _non_expense ->
        {:cancel, "not an expense invoice"}
    end
  end

  @spec run_classification(Invoices.Invoice.t()) :: :ok | {:cancel, String.t()} | {:error, term()}
  defp run_classification(invoice) do
    case InvoiceClassifier.predict_and_apply(invoice) do
      {:ok, _invoice} ->
        :ok

      {:skip, reason} ->
        {:cancel, "skipped: #{reason}"}

      {:error, :classifier_not_configured} ->
        {:cancel, "classification service not configured"}

      {:error, reason} ->
        Logger.error(
          "Classification failed for invoice #{invoice.id}: #{inspect(reason, limit: 200)}"
        )

        {:error, reason}
    end
  end
end
