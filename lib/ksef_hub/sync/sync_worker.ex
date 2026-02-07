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
  def perform(%Oban.Job{}) do
    with {:ok, credential} <- load_active_credential(),
         {:ok, access_token} <- get_access_token() do
      result = sync_all_types(access_token, credential.nip)
      Credentials.update_last_sync(credential)
      result
    else
      {:error, :no_credential} ->
        Logger.info("Sync skipped: no active credential configured")
        :ok

      {:error, :reauth_required} ->
        Logger.warning("Sync skipped: XADES re-authentication required")
        {:error, :reauth_required}

      {:error, reason} ->
        Logger.error("Sync failed: #{inspect(reason)}")
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

  defp sync_all_types(access_token, nip) do
    income_result = sync_type(access_token, "income", nip)
    expense_result = sync_type(access_token, "expense", nip)

    case {income_result, expense_result} do
      {{:ok, ic}, {:ok, ec}} ->
        Logger.info("Sync complete: #{ic} income, #{ec} expense invoices")
        :ok

      {{:error, reason}, _} ->
        {:error, reason}

      {_, {:error, reason}} ->
        {:error, reason}
    end
  end

  defp sync_type(access_token, type, nip) do
    checkpoint = Checkpoints.get_or_init(type, nip)

    case InvoiceFetcher.fetch_all(access_token, type, nip, checkpoint.last_seen_timestamp) do
      {:ok, count, nil} ->
        {:ok, count}

      {:ok, count, max_timestamp} ->
        Checkpoints.advance(type, nip, max_timestamp)
        {:ok, count}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
