defmodule KsefHub.Accounts.ApiTokens do
  @moduledoc """
  Manages API token lifecycle: creation, validation, revocation, listing, and usage tracking.

  Tokens are hashed before storage (SHA-256) and never persisted in plaintext.
  The raw token is returned exactly once on creation.
  """

  import Ecto.Query

  alias KsefHub.Accounts.ApiToken
  alias KsefHub.ActivityLog.TrackedRepo
  alias KsefHub.Authorization
  alias KsefHub.Repo

  @token_bytes 32

  @doc """
  Creates a new API token owned by the given user (no company scope).
  Returns the plaintext token exactly once.

  Kept for backward compatibility. Prefer `create_api_token/3` for new code.
  """
  @spec create_api_token(Ecto.UUID.t(), map()) ::
          {:ok, %{token: String.t(), api_token: ApiToken.t()}} | {:error, Ecto.Changeset.t()}
  def create_api_token(user_id, attrs) do
    do_create_api_token(user_id, nil, attrs)
  end

  @doc """
  Creates a new API token scoped to a company.
  All company members can create tokens.
  Returns the plaintext token exactly once.

  ## Parameters
    - `user_id` — the creating user's ID
    - `company_id` — the company to scope the token to
    - `attrs` — token attributes (`:name`, `:description`, `:expires_at`)

  ## Returns
    - `{:ok, %{token: String.t(), api_token: ApiToken.t()}}` on success
    - `{:error, :unauthorized}` if user does not have token management permission
    - `{:error, Ecto.Changeset.t()}` on validation failure
  """
  @spec create_api_token(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, %{token: String.t(), api_token: ApiToken.t()}}
          | {:error, :unauthorized}
          | {:error, Ecto.Changeset.t()}
  def create_api_token(user_id, company_id, attrs) do
    if Authorization.can?(user_id, company_id, :manage_tokens) do
      do_create_api_token(user_id, company_id, attrs)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Validates a plaintext API token. Returns the token record with company preloaded
  if valid and not expired.

  ## Returns
    - `{:ok, ApiToken.t()}` if valid and active (company preloaded)
    - `{:error, :invalid}` if not found or not a binary
    - `{:error, :expired}` if past `expires_at`
  """
  @spec validate_api_token(String.t()) ::
          {:ok, ApiToken.t()} | {:error, :invalid} | {:error, :expired}
  def validate_api_token(plain_token) when is_binary(plain_token) do
    token_hash = hash_token(plain_token)

    query =
      from(t in ApiToken,
        where: t.token_hash == ^token_hash and t.is_active == true,
        preload: [:company]
      )

    case Repo.one(query) do
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

  def validate_api_token(_), do: {:error, :invalid}

  @doc """
  Revokes an API token by ID, scoped to the given user.
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
        |> TrackedRepo.update(user_id: user_id)
    end
  end

  @doc """
  Revokes an API token by ID, scoped to the given user and company.
  All company members can revoke their own tokens.

  ## Returns
    - `{:ok, ApiToken.t()}` on success
    - `{:error, :unauthorized}` if user does not have token management permission
    - `{:error, :not_found}` if the token doesn't exist for user + company
    - `{:error, Ecto.Changeset.t()}` on update failure
  """
  @spec revoke_api_token(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, ApiToken.t()}
          | {:error, :unauthorized}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def revoke_api_token(user_id, company_id, token_id) do
    if Authorization.can?(user_id, company_id, :manage_tokens) do
      do_revoke_api_token(user_id, company_id, token_id)
    else
      {:error, :unauthorized}
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
    |> redact_token_hashes()
  end

  @doc """
  Lists API tokens for a given user and company with sensitive fields redacted.
  """
  @spec list_api_tokens(Ecto.UUID.t(), Ecto.UUID.t()) :: [ApiToken.t()]
  def list_api_tokens(user_id, company_id) do
    ApiToken
    |> where([t], t.created_by_id == ^user_id and t.company_id == ^company_id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
    |> redact_token_hashes()
  end

  @doc """
  Tracks usage of an API token (last_used_at, request_count).
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

  @spec do_create_api_token(Ecto.UUID.t(), Ecto.UUID.t() | nil, map()) ::
          {:ok, %{token: String.t(), api_token: ApiToken.t()}} | {:error, Ecto.Changeset.t()}
  defp do_create_api_token(user_id, company_id, attrs) do
    plain_token = generate_token()
    token_hash = hash_token(plain_token)
    token_prefix = String.slice(plain_token, 0, 8)

    changeset =
      %ApiToken{created_by_id: user_id, company_id: company_id}
      |> ApiToken.changeset(attrs)
      |> Ecto.Changeset.put_change(:token_hash, token_hash)
      |> Ecto.Changeset.put_change(:token_prefix, token_prefix)

    case TrackedRepo.insert(changeset, user_id: user_id) do
      {:ok, api_token} ->
        {:ok, %{token: plain_token, api_token: api_token}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec do_revoke_api_token(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, ApiToken.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  defp do_revoke_api_token(user_id, company_id, token_id) do
    case Repo.get_by(ApiToken,
           id: token_id,
           created_by_id: user_id,
           company_id: company_id
         ) do
      nil ->
        {:error, :not_found}

      api_token ->
        api_token
        |> ApiToken.changeset(%{is_active: false})
        |> TrackedRepo.update(user_id: user_id)
    end
  end

  @spec redact_token_hashes([ApiToken.t()]) :: [ApiToken.t()]
  defp redact_token_hashes(tokens) do
    Enum.map(tokens, fn token -> %{token | token_hash: "**redacted**"} end)
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
