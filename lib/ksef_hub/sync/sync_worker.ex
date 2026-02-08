defmodule KsefHub.Sync.SyncWorker do
  @moduledoc """
  Oban worker that syncs invoices from KSeF for a specific company.
  Dispatched by SyncDispatcher for each company with an active credential.
  """

  use Oban.Worker, queue: :sync, max_attempts: 3

  require Logger

  alias KsefHub.Credentials
  alias KsefHub.KsefClient.TokenManager
  alias KsefHub.Sync.{Checkpoints, InvoiceFetcher}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"company_id" => company_id}} = job) do
    with {:ok, credential} <- load_active_credential(company_id),
         {:ok, access_token} <- get_access_token(company_id) do
      access_token
      |> sync_all_types(credential.nip, company_id, job)
      |> handle_sync_result(credential)
    else
      {:error, :no_credential} ->
        Logger.info("Sync skipped for company #{company_id}: no active credential configured")
        :ok

      {:error, :reauth_required} ->
        Logger.warning("Sync skipped for company #{company_id}: XADES re-authentication required")
        store_meta(job, %{"error" => "reauth_required"})
        {:cancel, :reauth_required}

      {:error, reason} ->
        Logger.error("Sync failed for company #{company_id}: #{inspect(reason)}")
        store_meta(job, %{"error" => inspect(reason)})
        {:error, reason}
    end
  end

  # Legacy: support jobs without company_id (backward compat during migration)
  def perform(%Oban.Job{}) do
    Logger.info("Sync skipped: job missing company_id arg")
    :ok
  end

  defp load_active_credential(company_id) do
    case Credentials.get_active_credential(company_id) do
      nil -> {:error, :no_credential}
      cred -> {:ok, cred}
    end
  end

  defp handle_sync_result({:ok, :full}, credential) do
    case Credentials.update_last_sync(credential) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:last_sync_update_failed, reason}}
    end
  end

  defp handle_sync_result({:ok, :partial, _details}, _credential), do: :ok
  defp handle_sync_result({:error, reason}, _credential), do: {:error, reason}

  defp get_access_token(company_id) do
    TokenManager.ensure_access_token(company_id)
  end

  defp sync_all_types(access_token, nip, company_id, job) do
    income_result = sync_type(access_token, "income", nip, company_id)
    expense_result = sync_type(access_token, "expense", nip, company_id)

    case {income_result, expense_result} do
      {{:ok, ic}, {:ok, ec}} ->
        Logger.info(
          "Sync complete for company #{company_id}: #{ic} income, #{ec} expense invoices"
        )

        store_meta(job, %{"income_count" => ic, "expense_count" => ec})
        broadcast_sync_completed(company_id, %{income: ic, expense: ec})
        {:ok, :full}

      {{:ok, ic}, {:error, reason}} ->
        Logger.error(
          "Expense sync failed for company #{company_id}: #{inspect(reason)} (#{ic} income invoices synced)"
        )

        store_meta(job, %{
          "income_count" => ic,
          "error" => inspect(reason),
          "failed_type" => "expense"
        })

        {:ok, :partial, %{succeeded: :income, failed: {:expense, reason}}}

      {{:error, reason}, {:ok, ec}} ->
        Logger.error(
          "Income sync failed for company #{company_id}: #{inspect(reason)} (#{ec} expense invoices synced)"
        )

        store_meta(job, %{
          "expense_count" => ec,
          "error" => inspect(reason),
          "failed_type" => "income"
        })

        {:ok, :partial, %{succeeded: :expense, failed: {:income, reason}}}

      {{:error, income_reason}, {:error, expense_reason}} ->
        Logger.error(
          "Both syncs failed for company #{company_id} — income: #{inspect(income_reason)}, expense: #{inspect(expense_reason)}"
        )

        store_meta(job, %{
          "income_error" => inspect(income_reason),
          "expense_error" => inspect(expense_reason)
        })

        {:error, {income_reason, expense_reason}}
    end
  end

  defp broadcast_sync_completed(company_id, stats) do
    case Phoenix.PubSub.broadcast(
           KsefHub.PubSub,
           "sync:status:#{company_id}",
           {:sync_completed, stats}
         ) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to broadcast sync status: #{inspect(reason)}")
        :ok
    end
  end

  defp sync_type(access_token, type, nip, company_id) do
    checkpoint = Checkpoints.get_or_init(type, company_id)

    case InvoiceFetcher.fetch_all(
           access_token,
           type,
           nip,
           company_id,
           checkpoint.last_seen_timestamp
         ) do
      {:ok, count, nil} ->
        {:ok, count}

      {:ok, count, max_timestamp} ->
        case Checkpoints.advance(type, company_id, max_timestamp) do
          {:ok, _checkpoint} ->
            {:ok, count}

          {:error, reason} ->
            {:error, {:checkpoint_advance_failed, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp store_meta(%Oban.Job{id: id}, attrs) when is_integer(id) do
    import Ecto.Query, only: [where: 2]

    Oban.Job
    |> where(id: ^id)
    |> KsefHub.Repo.update_all(set: [meta: attrs])
  end

  defp store_meta(_job, _attrs), do: :ok
end
