defmodule KsefHub.InvoiceClassifier.Worker do
  @moduledoc """
  Oban worker that runs ML classification for newly created expense invoices.

  Enqueued after invoice creation (sync or manual). Skips income invoices,
  already-manual predictions, and missing invoices. Cancels permanently on
  configuration errors (won't help to retry).

  Supports an optional `"on_complete"` map in job args. When present, the
  specified worker is enqueued after classification finishes — regardless of
  outcome (success, skip, or permanent failure). This enables job chaining
  (e.g. sending a reply email after classification).
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias KsefHub.InvoiceClassifier
  alias KsefHub.Invoices

  @doc """
  Conditionally enqueues a classification job for an expense invoice.

  Returns `{:ok, %Oban.Job{}}` for expense invoices, `{:error, changeset}`
  on Oban insert failure, or `:skip` for non-expense invoices.

  Accepts an optional `on_complete` map that is forwarded to the job args.
  When set, the specified worker will be enqueued after classification finishes.
  """
  @spec maybe_enqueue(Invoices.Invoice.t(), keyword()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | :skip
  def maybe_enqueue(invoice, opts \\ [])

  def maybe_enqueue(%{type: :expense, id: id, company_id: company_id}, opts) do
    args = %{invoice_id: id, company_id: company_id}

    args =
      case Keyword.get(opts, :on_complete) do
        nil -> args
        on_complete when is_map(on_complete) -> Map.put(args, :on_complete, on_complete)
      end

    args
    |> new()
    |> Oban.insert()
  end

  def maybe_enqueue(_invoice, _opts), do: :skip

  @doc """
  Oban entry point: classifies an expense invoice via the ML sidecar.

  Looks up the invoice by `"invoice_id"` and `"company_id"` from job args.
  Returns `:ok` on success, `{:cancel, reason}` for non-retryable cases
  (missing invoice, non-expense, already manual, service not configured),
  or `{:error, term()}` for transient failures.

  When classification completes (success or cancel) and `"on_complete"` args
  are present, the chained worker is enqueued. On transient errors, the chain
  is NOT triggered — Oban will retry the job, and the chain runs after success
  or final cancellation.
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:cancel, String.t()} | {:error, term()}
  def perform(%Oban.Job{args: args}) do
    %{"invoice_id" => invoice_id, "company_id" => company_id} = args

    result =
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

    maybe_run_on_complete(result, args)
    result
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

  # Enqueue the chained worker on terminal outcomes (success or cancel).
  # Transient errors are NOT terminal — Oban will retry, and the chain
  # triggers after the retry succeeds or the job is finally cancelled.
  @spec maybe_run_on_complete(term(), map()) :: :ok
  defp maybe_run_on_complete({:error, _}, _args), do: :ok

  defp maybe_run_on_complete(_result, %{
         "on_complete" => %{"worker" => worker_module, "args" => worker_args}
       }) do
    worker = String.to_existing_atom("Elixir.#{worker_module}")

    case Oban.insert(worker.new(worker_args)) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to enqueue on_complete worker #{worker_module}: #{inspect(reason)}")

        :ok
    end
  rescue
    e in ArgumentError ->
      Logger.error(
        "Failed to resolve on_complete worker #{worker_module}: #{Exception.message(e)}"
      )

      :ok
  end

  defp maybe_run_on_complete(_result, _args), do: :ok
end
