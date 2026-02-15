defmodule KsefHub.Sync.SyncWorker do
  @moduledoc """
  Oban worker that syncs invoices from KSeF for a specific company.
  Dispatched by SyncDispatcher for each company with an active credential.
  """

  use Oban.Worker, queue: :sync, max_attempts: 3

  require Logger

  alias KsefHub.Credentials
  alias KsefHub.KsefClient.{Authenticator, TokenManager}
  alias KsefHub.Sync.{Checkpoints, InvoiceFetcher}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"company_id" => company_id}} = job) do
    with {:ok, credential} <- load_active_credential(company_id),
         :ok <- verify_owner_certificate(company_id),
         {:ok, access_token} <- get_access_token(company_id) do
      sync_result = sync_all_types(access_token, credential.nip, company_id, job)

      # Terminate the KSeF session after sync completes successfully.
      # On failure, keep the session alive so Oban retries can reuse the token.
      unless match?({:error, _}, sync_result) do
        terminate_session_safely(access_token, company_id)
      end

      handle_sync_result(sync_result, credential)
    else
      {:error, :no_credential} ->
        Logger.warning(
          "Sync skipped for company #{company_id}: no active credential configured (create one in the UI)"
        )

        store_meta(job, %{"error" => "no_credential"})
        {:cancel, :no_credential}

      {:error, :no_certificate} ->
        Logger.warning(
          "Sync skipped for company #{company_id}: no owner certificate uploaded (upload one in the UI)"
        )

        store_meta(job, %{"error" => "no_certificate"})
        {:cancel, :no_certificate}

      {:error, {:reauth_failed, reason}} ->
        Logger.error(
          "Sync failed for company #{company_id}: re-authentication failed: #{inspect(reason)}"
        )

        store_meta(job, %{"error" => "reauth_failed: #{inspect(reason)}"})
        {:error, {:reauth_failed, reason}}

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

  @spec load_active_credential(Ecto.UUID.t()) ::
          {:ok, Credentials.Credential.t()} | {:error, :no_credential}
  defp load_active_credential(company_id) do
    case Credentials.get_active_credential(company_id) do
      nil -> {:error, :no_credential}
      cred -> {:ok, cred}
    end
  end

  @spec verify_owner_certificate(Ecto.UUID.t()) :: :ok | {:error, :no_certificate}
  defp verify_owner_certificate(company_id) do
    case Credentials.get_certificate_for_company(company_id) do
      nil -> {:error, :no_certificate}
      _cert -> :ok
    end
  end

  @spec handle_sync_result(
          {:ok, :full} | {:ok, :partial, map()} | {:error, term()},
          Credentials.Credential.t()
        ) :: :ok | {:error, term()}
  defp handle_sync_result({:ok, :full}, credential) do
    case Credentials.update_last_sync(credential) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:last_sync_update_failed, reason}}
    end
  end

  defp handle_sync_result({:ok, :partial, _details}, _credential), do: :ok
  defp handle_sync_result({:error, reason}, _credential), do: {:error, reason}

  @spec get_access_token(Ecto.UUID.t()) :: {:ok, String.t()} | {:error, term()}
  defp get_access_token(company_id) do
    case TokenManager.ensure_access_token(company_id) do
      {:ok, token} -> {:ok, token}
      {:error, :reauth_required} -> attempt_reauth(company_id)
      error -> error
    end
  end

  @permanent_reauth_errors [:no_credential, :no_certificate]

  @spec attempt_reauth(Ecto.UUID.t()) :: {:ok, String.t()} | {:error, term()}
  defp attempt_reauth(company_id) do
    Logger.info("Attempting XADES re-authentication for company #{company_id}")

    case Authenticator.authenticate_and_store(company_id) do
      {:ok, access_token} -> {:ok, access_token}
      {:error, reason} when reason in @permanent_reauth_errors -> {:error, reason}
      {:error, reason} -> {:error, {:reauth_failed, reason}}
    end
  end

  @spec sync_all_types(String.t(), String.t(), Ecto.UUID.t(), Oban.Job.t()) ::
          {:ok, :full} | {:ok, :partial, map()} | {:error, term()}
  defp sync_all_types(access_token, nip, company_id, job) do
    income_result = sync_type(access_token, "income", nip, company_id)
    expense_result = sync_type(access_token, "expense", nip, company_id)

    case {income_result, expense_result} do
      {{:ok, ic, if_}, {:ok, ec, ef}} ->
        handle_both_succeeded(company_id, job, ic, if_, ec, ef)

      {{:ok, ic, if_}, {:error, reason}} ->
        Logger.error(
          "Expense sync failed for company #{company_id}: #{inspect(reason)} (#{ic} income invoices synced)"
        )

        meta = %{
          "income_count" => ic,
          "error" => inspect(reason),
          "failed_type" => "expense"
        }

        meta = if if_ > 0, do: Map.put(meta, "income_failed", if_), else: meta
        store_meta(job, meta)

        {:ok, :partial, %{succeeded: :income, failed: {:expense, reason}}}

      {{:error, reason}, {:ok, ec, ef}} ->
        Logger.error(
          "Income sync failed for company #{company_id}: #{inspect(reason)} (#{ec} expense invoices synced)"
        )

        meta = %{
          "expense_count" => ec,
          "error" => inspect(reason),
          "failed_type" => "income"
        }

        meta = if ef > 0, do: Map.put(meta, "expense_failed", ef), else: meta
        store_meta(job, meta)

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

  @spec handle_both_succeeded(
          Ecto.UUID.t(),
          Oban.Job.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, :full} | {:ok, :partial, map()}
  defp handle_both_succeeded(company_id, job, ic, if_, ec, ef) do
    total_failed = if_ + ef

    if total_failed > 0 do
      Logger.warning(
        "Sync complete for company #{company_id}: #{ic} income, #{ec} expense invoices (#{total_failed} failed downloads)"
      )
    else
      Logger.info("Sync complete for company #{company_id}: #{ic} income, #{ec} expense invoices")
    end

    meta = %{"income_count" => ic, "expense_count" => ec}

    meta =
      if total_failed > 0,
        do: Map.put(meta, "error", "#{total_failed} invoice downloads failed"),
        else: meta

    store_meta(job, meta)
    broadcast_sync_completed(company_id, %{income: ic, expense: ec})

    if total_failed > 0 do
      {:ok, :partial, %{failed_downloads: total_failed}}
    else
      {:ok, :full}
    end
  end

  @spec broadcast_sync_completed(Ecto.UUID.t(), map()) :: :ok
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

  @spec sync_type(String.t(), String.t(), String.t(), Ecto.UUID.t()) ::
          {:ok, non_neg_integer(), non_neg_integer()} | {:error, term()}
  defp sync_type(access_token, type, nip, company_id) do
    checkpoint = Checkpoints.get_or_init(type, company_id)

    case InvoiceFetcher.fetch_all(
           access_token,
           type,
           nip,
           company_id,
           checkpoint.last_seen_timestamp
         ) do
      {:ok, count, nil, failed} ->
        {:ok, count, failed}

      {:ok, count, _max_timestamp, failed} when failed > 0 ->
        {:ok, count, failed}

      {:ok, count, max_timestamp, failed} ->
        case Checkpoints.advance(type, company_id, max_timestamp) do
          {:ok, _checkpoint} ->
            {:ok, count, failed}

          {:error, reason} ->
            {:error, {:checkpoint_advance_failed, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec terminate_session_safely(String.t(), Ecto.UUID.t()) :: :ok
  defp terminate_session_safely(access_token, company_id) do
    case ksef_client().terminate_session(access_token) do
      :ok ->
        Logger.info("KSeF session terminated for company #{company_id}")

      {:error, reason} ->
        Logger.warning(
          "Failed to terminate KSeF session for company #{company_id}: #{inspect(reason)}"
        )
    end

    :ok
  end

  @spec ksef_client() :: module()
  defp ksef_client, do: Application.get_env(:ksef_hub, :ksef_client, KsefHub.KsefClient.Live)

  @spec store_meta(Oban.Job.t(), map()) :: :ok | {non_neg_integer(), nil}
  defp store_meta(%Oban.Job{id: id}, attrs) when is_integer(id) do
    import Ecto.Query, only: [where: 2]

    Oban.Job
    |> where(id: ^id)
    |> KsefHub.Repo.update_all(set: [meta: attrs])
  end

  defp store_meta(_job, _attrs), do: :ok
end
