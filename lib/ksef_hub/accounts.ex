defmodule KsefHub.Accounts do
  @moduledoc """
  The Accounts context. Manages users and API tokens.
  """

  import Ecto.Query

  alias KsefHub.Accounts.{ApiToken, User}
  alias KsefHub.Repo

  @token_bytes 32

  # --- Users ---

  @doc "Fetches a user by UUID, returning `nil` if not found."
  @spec get_user(Ecto.UUID.t()) :: User.t() | nil
  def get_user(id), do: Repo.get(User, id)

  @doc "Fetches a user by UUID, raising `Ecto.NoResultsError` if not found."
  @spec get_user!(Ecto.UUID.t()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  @doc "Fetches a user by email address, returning `nil` if not found."
  @spec get_user_by_email(String.t()) :: User.t() | nil
  def get_user_by_email(email), do: Repo.get_by(User, email: email)

  @doc "Fetches a user by Google UID, returning `nil` if not found."
  @spec get_user_by_google_uid(String.t()) :: User.t() | nil
  def get_user_by_google_uid(uid), do: Repo.get_by(User, google_uid: uid)

  @doc """
  Finds a user by Google UID, or creates one from Google auth info.
  Returns `{:ok, user}` or `{:error, changeset}`.
  """
  @spec find_or_create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def find_or_create_user(%{uid: uid, email: email} = info) do
    case get_user_by_google_uid(uid) do
      nil ->
        changeset =
          %User{}
          |> User.changeset(%{
            google_uid: uid,
            email: email,
            name: Map.get(info, :name),
            avatar_url: Map.get(info, :avatar_url)
          })

        case Repo.insert(changeset, on_conflict: :nothing, conflict_target: :google_uid) do
          {:ok, %User{id: nil}} ->
            {:ok, get_user_by_google_uid(uid)}

          result ->
            result
        end

      user ->
        {:ok, user}
    end
  end

  @doc """
  Checks if an email is in the allowlist.
  """
  @spec allowed_email?(String.t()) :: boolean()
  def allowed_email?(email) when is_binary(email) do
    String.downcase(email) in allowed_emails()
  end

  @spec allowed_emails() :: [String.t()]
  defp allowed_emails do
    :persistent_term.get({__MODULE__, :allowed_emails}, nil) || parse_and_cache_allowed_emails()
  end

  @spec parse_and_cache_allowed_emails() :: [String.t()]
  defp parse_and_cache_allowed_emails do
    list =
      Application.get_env(:ksef_hub, :allowed_emails, "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.downcase/1)

    :persistent_term.put({__MODULE__, :allowed_emails}, list)
    list
  end

  @doc """
  Clears the cached allowed emails list. Call when the config changes.
  """
  @spec clear_allowed_emails_cache() :: :ok
  def clear_allowed_emails_cache do
    :persistent_term.erase({__MODULE__, :allowed_emails})
    :ok
  end

  # --- API Tokens ---

  @doc """
  Creates a new API token owned by the given user. Returns the plaintext token exactly once.
  """
  @spec create_api_token(Ecto.UUID.t(), map()) ::
          {:ok, %{token: String.t(), api_token: ApiToken.t()}} | {:error, Ecto.Changeset.t()}
  def create_api_token(user_id, attrs) do
    attrs = Map.put(attrs, :created_by_id, user_id)
    do_create_api_token(attrs)
  end

  @spec do_create_api_token(map()) ::
          {:ok, %{token: String.t(), api_token: ApiToken.t()}} | {:error, Ecto.Changeset.t()}
  defp do_create_api_token(attrs) do
    plain_token = generate_token()
    token_hash = hash_token(plain_token)
    token_prefix = String.slice(plain_token, 0, 8)

    changeset =
      %ApiToken{}
      |> ApiToken.changeset(attrs)
      |> Ecto.Changeset.put_change(:token_hash, token_hash)
      |> Ecto.Changeset.put_change(:token_prefix, token_prefix)

    case Repo.insert(changeset) do
      {:ok, api_token} ->
        {:ok, %{token: plain_token, api_token: api_token}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Validates a plaintext API token. Returns the token record if valid and not expired.
  """
  @spec validate_api_token(String.t()) ::
          {:ok, ApiToken.t()} | {:error, :invalid} | {:error, :expired}
  def validate_api_token(plain_token) do
    token_hash = hash_token(plain_token)

    case Repo.get_by(ApiToken, token_hash: token_hash, is_active: true) do
      nil ->
        {:error, :invalid}

      %ApiToken{expires_at: expires_at} = api_token when not is_nil(expires_at) ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
          {:ok, api_token}
        else
          {:error, :expired}
        end

      api_token ->
        {:ok, api_token}
    end
  end

  @doc """
  Revokes an API token by ID, scoped to the given user.
  Returns `{:error, :not_found}` if the token doesn't exist or doesn't belong to the user.
  """
  @spec revoke_api_token(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, ApiToken.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def revoke_api_token(user_id, token_id) do
    case Repo.get_by(ApiToken, id: token_id, created_by_id: user_id) do
      nil ->
        {:error, :not_found}

      api_token ->
        api_token
        |> ApiToken.changeset(%{is_active: false})
        |> Repo.update()
    end
  end

  @doc """
  Lists API tokens for a given user with sensitive fields redacted.
  """
  @spec list_api_tokens(Ecto.UUID.t()) :: [ApiToken.t()]
  def list_api_tokens(user_id) do
    ApiToken
    |> where([t], t.created_by_id == ^user_id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
    |> Enum.map(fn token -> %{token | token_hash: "**redacted**"} end)
  end

  @doc """
  Tracks usage of an API token (last_used_at, request_count).
  Returns `:ok` if the token was found, `{:error, :not_found}` otherwise.
  """
  @spec track_token_usage(Ecto.UUID.t()) :: :ok | {:error, :not_found}
  def track_token_usage(token_id) do
    case from(t in ApiToken, where: t.id == ^token_id)
         |> Repo.update_all(
           set: [last_used_at: DateTime.utc_now()],
           inc: [request_count: 1]
         ) do
      {1, _} -> :ok
      {0, _} -> {:error, :not_found}
    end
  end

  @spec generate_token() :: String.t()
  defp generate_token do
    @token_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @spec hash_token(String.t()) :: String.t()
  defp hash_token(token) do
    :crypto.hash(:sha256, token)
    |> Base.encode16(case: :lower)
  end
end
