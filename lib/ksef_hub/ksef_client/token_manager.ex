defmodule KsefHub.KsefClient.TokenManager do
  @moduledoc """
  Per-company GenServer that manages KSeF access/refresh token lifecycle.
  Uses Registry + DynamicSupervisor for per-company instances.

  - Holds current access_token and refresh_token with expiry times
  - Auto-refreshes access_token before expiry
  - Persists refresh_token encrypted in DB for restart recovery
  - Returns {:error, :reauth_required} when refresh_token expires
  - Idle timeout (30 min) to clean up unused instances
  """

  use GenServer

  require Logger

  alias KsefHub.Credentials
  alias KsefHub.Credentials.{Credential, Encryption}

  @refresh_buffer_seconds 120
  @idle_timeout :timer.minutes(30)

  # --- Client API ---

  @doc """
  Returns a valid access token for the given company, refreshing if needed.
  Starts the instance if not already running.
  """
  @spec ensure_access_token(Ecto.UUID.t()) :: {:ok, String.t()} | {:error, term()}
  def ensure_access_token(company_id) do
    case ensure_started(company_id) do
      {:ok, pid} -> GenServer.call(pid, :ensure_access_token, 30_000)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stores new tokens after XADES authentication for a company.
  """
  @spec store_tokens(Ecto.UUID.t(), String.t(), String.t(), DateTime.t(), DateTime.t()) :: :ok
  def store_tokens(
        company_id,
        access_token,
        refresh_token,
        access_valid_until,
        refresh_valid_until
      ) do
    case ensure_started(company_id) do
      {:ok, pid} ->
        GenServer.call(
          pid,
          {:store_tokens, access_token, refresh_token, access_valid_until, refresh_valid_until}
        )

      {:error, reason} ->
        Logger.warning("Failed to store tokens for company #{company_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Returns the refresh token expiry for alerting.
  """
  @spec refresh_token_expires_at(Ecto.UUID.t()) :: DateTime.t() | nil
  def refresh_token_expires_at(company_id) do
    case ensure_started(company_id) do
      {:ok, pid} -> GenServer.call(pid, :refresh_token_expires_at)
      {:error, _} -> nil
    end
  end

  @doc """
  Starts a TokenManager instance for the given company if not running.
  """
  @spec ensure_started(Ecto.UUID.t()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(company_id) do
    case Registry.lookup(KsefHub.TokenManagerRegistry, company_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        DynamicSupervisor.start_child(
          KsefHub.TokenManagerSupervisor,
          {__MODULE__, company_id}
        )
        |> case do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def start_link(company_id) do
    GenServer.start_link(__MODULE__, company_id, name: via(company_id))
  end

  defp via(company_id), do: {:via, Registry, {KsefHub.TokenManagerRegistry, company_id}}

  # --- Server Callbacks ---

  @impl true
  def init(company_id) do
    state = load_from_db(company_id)
    {:ok, state, @idle_timeout}
  end

  @impl true
  def handle_call(:ensure_access_token, _from, state) do
    case ensure_valid_access(state) do
      {:ok, access_token, new_state} ->
        {:reply, {:ok, access_token}, new_state, @idle_timeout}

      {:error, reason} ->
        {:reply, {:error, reason}, state, @idle_timeout}
    end
  end

  @impl true
  def handle_call({:store_tokens, access, refresh, access_until, refresh_until}, _from, state) do
    new_state = %{
      state
      | access_token: access,
        refresh_token: refresh,
        access_valid_until: access_until,
        refresh_valid_until: refresh_until
    }

    persist_to_db(new_state)
    {:reply, :ok, new_state, @idle_timeout}
  end

  @impl true
  def handle_call(:refresh_token_expires_at, _from, state) do
    {:reply, state.refresh_valid_until, state, @idle_timeout}
  end

  @impl true
  def handle_info(:timeout, state) do
    Logger.debug("TokenManager for company #{state.company_id} idle timeout, stopping")
    {:stop, :normal, state}
  end

  # --- Private ---

  defp ensure_valid_access(state) do
    cond do
      state.access_token == nil ->
        {:error, :reauth_required}

      access_token_valid?(state) ->
        {:ok, state.access_token, state}

      state.refresh_token != nil && refresh_token_valid?(state) ->
        do_refresh(state)

      true ->
        {:error, :reauth_required}
    end
  end

  defp access_token_valid?(%{access_valid_until: nil}), do: false

  defp access_token_valid?(%{access_valid_until: valid_until}) do
    DateTime.compare(valid_until, DateTime.add(DateTime.utc_now(), @refresh_buffer_seconds)) ==
      :gt
  end

  defp refresh_token_valid?(%{refresh_valid_until: nil}), do: false

  defp refresh_token_valid?(%{refresh_valid_until: valid_until}) do
    DateTime.compare(valid_until, DateTime.utc_now()) == :gt
  end

  defp do_refresh(state) do
    ksef_client = Application.get_env(:ksef_hub, :ksef_client, KsefHub.KsefClient.Live)

    case ksef_client.refresh_access_token(state.refresh_token) do
      {:ok, %{access_token: new_access, valid_until: new_valid_until}} ->
        new_state = %{state | access_token: new_access, access_valid_until: new_valid_until}
        persist_to_db(new_state)
        {:ok, new_access, new_state}

      {:error, _} = error ->
        Logger.warning("Token refresh failed, re-auth required")
        error
    end
  end

  defp load_from_db(company_id) do
    case Credentials.get_active_credential(company_id) do
      nil ->
        empty_state(company_id)

      cred ->
        %{
          company_id: company_id,
          access_token: decrypt_token(cred.access_token_encrypted),
          refresh_token: decrypt_token(cred.refresh_token_encrypted),
          access_valid_until: cred.access_token_expires_at,
          refresh_valid_until: cred.refresh_token_expires_at,
          credential_id: cred.id
        }
    end
  end

  defp persist_to_db(%{credential_id: nil}), do: :ok

  defp persist_to_db(%{credential_id: cred_id} = state) do
    case KsefHub.Repo.get(Credential, cred_id) do
      nil ->
        :ok

      cred ->
        Credentials.store_tokens(cred, %{
          access_token_encrypted: encrypt_token(state.access_token),
          access_token_expires_at: state.access_valid_until,
          refresh_token_encrypted: encrypt_token(state.refresh_token),
          refresh_token_expires_at: state.refresh_valid_until
        })
    end
  end

  defp encrypt_token(nil), do: nil

  defp encrypt_token(token) do
    {:ok, encrypted} = Encryption.encrypt(token)
    encrypted
  rescue
    e ->
      Logger.warning("Failed to encrypt token: #{Exception.message(e)}")
      nil
  end

  defp decrypt_token(nil), do: nil

  defp decrypt_token(encrypted) do
    case Encryption.decrypt(encrypted) do
      {:ok, token} ->
        token

      {:error, reason} ->
        Logger.warning("Failed to decrypt token: #{inspect(reason)}")
        nil
    end
  end

  defp empty_state(company_id) do
    %{
      company_id: company_id,
      access_token: nil,
      refresh_token: nil,
      access_valid_until: nil,
      refresh_valid_until: nil,
      credential_id: nil
    }
  end
end
