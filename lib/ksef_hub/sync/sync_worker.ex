defmodule KsefHub.Sync.SyncWorker do
  @moduledoc """
  Oban worker that syncs invoices from KSeF every 15 minutes.
  Uses TokenManager for access tokens (no XADES signing during regular sync).
  Implements incremental sync with checkpoint management and deduplication.
  """

  use Oban.Worker, queue: :sync, max_attempts: 3

  require Logger

  alias KsefHub.Credentials
  alias KsefHub.KsefClient.TokenManager
  alias KsefHub.Sync.{Checkpoints, InvoiceFetcher}

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    with {:ok, credential} <- load_active_credential(),
         {:ok, access_token} <- get_access_token() do
      case sync_all_types(access_token, credential.nip, job) do
        :ok ->
          Credentials.update_last_sync(credential)
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :no_credential} ->
        Logger.info("Sync skipped: no active credential configured")
        :ok

      {:error, :reauth_required} ->
        Logger.warning("Sync skipped: XADES re-authentication required")
        store_meta(job, %{"error" => "reauth_required"})
        {:cancel, :reauth_required}

      {:error, reason} ->
        Logger.error("Sync failed: #{inspect(reason)}")
        store_meta(job, %{"error" => inspect(reason)})
        {:error, reason}
    end
  end

  defp load_active_credential do
    case Credentials.get_active_credential() do
      nil -> {:error, :no_credential}
      cred -> {:ok, cred}
    end
  end

  defp get_access_token do
    case Process.whereis(TokenManager) do
      nil -> {:error, :reauth_required}
      _pid -> TokenManager.ensure_access_token()
    end
  end

  defp sync_all_types(access_token, nip, job) do
    income_result = sync_type(access_token, "income", nip)
    expense_result = sync_type(access_token, "expense", nip)

    case {income_result, expense_result} do
      {{:ok, ic}, {:ok, ec}} ->
        Logger.info("Sync complete: #{ic} income, #{ec} expense invoices")
        store_meta(job, %{"income_count" => ic, "expense_count" => ec})
        broadcast_sync_completed(%{income: ic, expense: ec})
        :ok

      {{:ok, ic}, {:error, reason}} ->
        Logger.error("Expense sync failed: #{inspect(reason)} (#{ic} income invoices synced)")
        store_meta(job, %{"income_count" => ic, "error" => inspect(reason)})
        :ok

      {{:error, reason}, {:ok, ec}} ->
        Logger.error("Income sync failed: #{inspect(reason)} (#{ec} expense invoices synced)")
        store_meta(job, %{"expense_count" => ec, "error" => inspect(reason)})
        :ok

      {{:error, income_reason}, {:error, expense_reason}} ->
        Logger.error(
          "Both syncs failed — income: #{inspect(income_reason)}, expense: #{inspect(expense_reason)}"
        )
        store_meta(job, %{"error" => inspect(income_reason)})
        {:error, income_reason}
    end
  end

  defp broadcast_sync_completed(stats) do
    case Phoenix.PubSub.broadcast(KsefHub.PubSub, "sync:status", {:sync_completed, stats}) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("Failed to broadcast sync status: #{inspect(reason)}")
    end
  end


  defp sync_type(access_token, type, nip) do
    checkpoint = Checkpoints.get_or_init(type, nip)

    case InvoiceFetcher.fetch_all(access_token, type, nip, checkpoint.last_seen_timestamp) do
      {:ok, count, nil} ->
        {:ok, count}

      {:ok, count, max_timestamp} ->
        case Checkpoints.advance(type, nip, max_timestamp) do
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
