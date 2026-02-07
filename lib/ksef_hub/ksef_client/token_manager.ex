defmodule KsefHub.KsefClient.TokenManager do
  @moduledoc """
  GenServer that manages KSeF access/refresh token lifecycle.
  - Holds current access_token and refresh_token with expiry times
  - Auto-refreshes access_token before expiry
  - Persists refresh_token encrypted in DB for restart recovery
  - Returns {:error, :reauth_required} when refresh_token expires
  """

  use GenServer

  require Logger

  alias KsefHub.Credentials

  @refresh_buffer_seconds 120

  @type state :: %{
          access_token: String.t() | nil,
          refresh_token: String.t() | nil,
          access_valid_until: DateTime.t() | nil,
          refresh_valid_until: DateTime.t() | nil,
          credential_id: Ecto.UUID.t() | nil
        }

  # --- Client API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns a valid access token, refreshing if needed.
  """
  @spec ensure_access_token() :: {:ok, String.t()} | {:error, :reauth_required | term()}
  def ensure_access_token do
    GenServer.call(__MODULE__, :ensure_access_token, 30_000)
  end

  @doc """
  Stores new tokens after XADES authentication.
  """
  @spec store_tokens(String.t(), String.t(), DateTime.t(), DateTime.t()) :: :ok
  def store_tokens(access_token, refresh_token, access_valid_until, refresh_valid_until) do
    GenServer.call(
      __MODULE__,
      {:store_tokens, access_token, refresh_token, access_valid_until, refresh_valid_until}
    )
  end

  @doc """
  Returns the refresh token expiry for alerting.
  """
  @spec refresh_token_expires_at() :: DateTime.t() | nil
  def refresh_token_expires_at do
    GenServer.call(__MODULE__, :refresh_token_expires_at)
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    state = load_from_db()
    {:ok, state}
  end

  @impl true
  def handle_call(:ensure_access_token, _from, state) do
    case ensure_valid_access(state) do
      {:ok, access_token, new_state} ->
        {:reply, {:ok, access_token}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
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
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:refresh_token_expires_at, _from, state) do
    {:reply, state.refresh_valid_until, state}
  end

  # --- Private ---

  @spec ensure_valid_access(state()) :: {:ok, String.t(), state()} | {:error, term()}
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

  @spec access_token_valid?(state()) :: boolean()
  defp access_token_valid?(%{access_valid_until: nil}), do: false

  defp access_token_valid?(%{access_valid_until: valid_until}) do
    DateTime.compare(valid_until, DateTime.add(DateTime.utc_now(), @refresh_buffer_seconds)) ==
      :gt
  end

  @spec refresh_token_valid?(state()) :: boolean()
  defp refresh_token_valid?(%{refresh_valid_until: nil}), do: false

  defp refresh_token_valid?(%{refresh_valid_until: valid_until}) do
    DateTime.compare(valid_until, DateTime.utc_now()) == :gt
  end

  @spec do_refresh(state()) :: {:ok, String.t(), state()} | {:error, term()}
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

  @spec load_from_db() :: state()
  defp load_from_db do
    case Credentials.get_active_credential() do
      nil ->
        empty_state()

      cred ->
        %{
          access_token: decrypt_token(cred.access_token_encrypted),
          refresh_token: decrypt_token(cred.refresh_token_encrypted),
          access_valid_until: cred.access_token_expires_at,
          refresh_valid_until: cred.refresh_token_expires_at,
          credential_id: cred.id
        }
    end
  end

  @spec persist_to_db(state()) ::
          :ok | {:ok, Credentials.Credential.t()} | {:error, Ecto.Changeset.t()}
  defp persist_to_db(%{credential_id: nil}), do: :ok

  defp persist_to_db(%{credential_id: cred_id} = state) do
    case KsefHub.Repo.get(KsefHub.Credentials.Credential, cred_id) do
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

  @spec encrypt_token(String.t() | nil) :: binary() | nil
  defp encrypt_token(nil), do: nil

  defp encrypt_token(plaintext) do
    {:ok, encrypted} = KsefHub.Credentials.Encryption.encrypt(plaintext)
    encrypted
  end

  @spec decrypt_token(binary() | nil) :: String.t() | nil
  defp decrypt_token(nil), do: nil

  defp decrypt_token(encrypted) do
    case KsefHub.Credentials.Encryption.decrypt(encrypted) do
      {:ok, token} -> token
      {:error, _} -> nil
    end
  end

  @spec empty_state() :: state()
  defp empty_state do
    %{
      access_token: nil,
      refresh_token: nil,
      access_valid_until: nil,
      refresh_valid_until: nil,
      credential_id: nil
    }
  end
end
