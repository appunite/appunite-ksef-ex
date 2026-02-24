defmodule KsefHub.Predictions.PredictionWorker do
  @moduledoc """
  Oban worker that runs ML predictions for newly created expense invoices.

  Enqueued after invoice creation (sync or manual). Skips income invoices,
  already-manual predictions, and missing invoices. Cancels permanently on
  configuration errors (won't help to retry).
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias KsefHub.Invoices
  alias KsefHub.Predictions

  @doc """
  Conditionally enqueues a prediction job for an expense invoice.

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

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:cancel, String.t()} | {:error, term()}
  def perform(%Oban.Job{args: %{"invoice_id" => invoice_id, "company_id" => company_id}}) do
    case Invoices.get_invoice(company_id, invoice_id) do
      nil ->
        {:cancel, "invoice not found"}

      %{prediction_status: :manual} ->
        {:cancel, "already manually classified"}

      %{type: :expense} = invoice ->
        run_prediction(invoice)

      _non_expense ->
        {:cancel, "not an expense invoice"}
    end
  end

  @spec run_prediction(Invoices.Invoice.t()) :: :ok | {:cancel, String.t()} | {:error, term()}
  defp run_prediction(invoice) do
    case Predictions.predict_and_apply(invoice) do
      {:ok, _invoice} ->
        :ok

      {:skip, reason} ->
        {:cancel, "skipped: #{reason}"}

      {:error, :prediction_service_not_configured} ->
        {:cancel, "prediction service not configured"}

      {:error, reason} ->
        Logger.error(
          "Prediction failed for invoice #{invoice.id}: #{inspect(reason, limit: 200)}"
        )

        {:error, reason}
    end
  end
end
