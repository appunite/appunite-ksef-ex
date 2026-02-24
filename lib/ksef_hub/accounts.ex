defmodule KsefHub.Accounts do
  @moduledoc """
  The Accounts context. Manages users, authentication, and API tokens.
  """

  import Ecto.Query

  alias KsefHub.Accounts.{ApiToken, User, UserNotifier, UserToken}
  alias KsefHub.Companies
  alias KsefHub.Repo

  @token_bytes 32

  # --- Users ---

  @doc """
  Fetches a user by UUID, returning `nil` if not found.

  ## Parameters
    - `id` (`Ecto.UUID.t()`) — the user's primary key

  ## Returns
    - `User.t() | nil`
  """
  @spec get_user(Ecto.UUID.t()) :: User.t() | nil
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Fetches a user by UUID, raising `Ecto.NoResultsError` if not found.

  ## Parameters
    - `id` (`Ecto.UUID.t()`) — the user's primary key

  ## Returns
    - `User.t()`
  """
  @spec get_user!(Ecto.UUID.t()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Fetches a user by email address, returning `nil` if not found.

  ## Parameters
    - `email` (`String.t()`) — the user's email address

  ## Returns
    - `User.t() | nil`
  """
  @spec get_user_by_email(String.t()) :: User.t() | nil
  def get_user_by_email(email), do: Repo.get_by(User, email: email)

  @doc """
  Fetches a user by Google UID, returning `nil` if not found.

  ## Parameters
    - `uid` (`String.t()`) — the Google-issued unique identifier

  ## Returns
    - `User.t() | nil`
  """
  @spec get_user_by_google_uid(String.t()) :: User.t() | nil
  def get_user_by_google_uid(uid), do: Repo.get_by(User, google_uid: uid)

  @doc """
  Fetches a user by email and verifies the password.

  Returns `nil` if no user found or password is invalid.
  """
  @spec get_user_by_email_and_password(String.t(), String.t()) :: User.t() | nil
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    normalized_email = email |> String.trim() |> String.downcase()
    user = get_user_by_email(normalized_email)
    if User.valid_password?(user, password), do: user
  end

  def get_user_by_email_and_password(_, _), do: nil

  @doc """
  Registers a new user with email and password.
  """
  @spec register_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user registration changes.
  """
  @spec change_registration(User.t(), map()) :: Ecto.Changeset.t()
  def change_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.
  """
  @spec change_user_password(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_password(%User{} = user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Finds a user by Google UID, links to existing email user, or creates a new one.

  Handles three cases:
  1. User exists with matching `google_uid` -> return existing
  2. User exists with matching `email` but no `google_uid` -> link Google UID
  3. No matching user -> create new
  """
  @spec get_or_create_google_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_google_user(%{uid: uid, email: email} = info) do
    normalized_email = String.downcase(email || "")

    Ecto.Multi.new()
    |> Ecto.Multi.run(:user, fn repo, _changes ->
      find_or_upsert_google_user(repo, uid, normalized_email, info)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} ->
        {:ok, user}

      {:error, :user, changeset, _changes} ->
        resolve_google_user_conflict(uid, normalized_email, changeset)
    end
  end

  @spec find_or_upsert_google_user(Ecto.Repo.t(), String.t(), String.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  defp find_or_upsert_google_user(repo, uid, email, info) do
    case repo.get_by(User, google_uid: uid) do
      %User{} = user -> {:ok, user}
      nil -> link_or_create_google_user(repo, uid, email, info)
    end
  end

  @spec link_or_create_google_user(Ecto.Repo.t(), String.t(), String.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  defp link_or_create_google_user(repo, uid, email, info) do
    case repo.get_by(User, email: email) do
      %User{} = user ->
        user
        |> User.changeset(%{
          google_uid: uid,
          name: Map.get(info, :name) || user.name,
          avatar_url: Map.get(info, :avatar_url) || user.avatar_url
        })
        |> repo.update()

      nil ->
        %User{}
        |> User.changeset(%{
          google_uid: uid,
          email: email,
          name: Map.get(info, :name),
          avatar_url: Map.get(info, :avatar_url)
        })
        |> repo.insert()
    end
  end

  @spec resolve_google_user_conflict(String.t(), String.t(), Ecto.Changeset.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  defp resolve_google_user_conflict(uid, email, %Ecto.Changeset{errors: errors} = changeset) do
    if Keyword.has_key?(errors, :email) or Keyword.has_key?(errors, :google_uid) do
      case get_user_by_google_uid(uid) || get_user_by_email(email) do
        %User{} = user -> {:ok, user}
        nil -> {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  # --- Session Tokens ---

  @doc """
  Generates a session token for the user and persists it.

  Returns the raw token to store in the session cookie.
  """
  @spec generate_user_session_token(User.t()) :: binary()
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user associated with a session token.

  Returns `nil` if the token is invalid or expired.
  """
  @spec get_user_by_session_token(binary()) :: User.t() | nil
  def get_user_by_session_token(token) when is_binary(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def get_user_by_session_token(_), do: nil

  @doc """
  Deletes the given session token from the database.
  """
  @spec delete_user_session_token(binary()) :: :ok
  def delete_user_session_token(token) when is_binary(token) do
    hashed_token = :crypto.hash(:sha256, token)

    from(t in UserToken, where: t.token == ^hashed_token and t.context == "session")
    |> Repo.delete_all()

    :ok
  end

  def delete_user_session_token(_), do: :ok

  # --- Email Confirmation ---

  @doc """
  Delivers confirmation instructions to the user.

  Returns `{:error, :already_confirmed}` if the user has already been confirmed.
  """
  @spec deliver_user_confirmation_instructions(User.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, :already_confirmed} | {:error, term()}
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      encoded = Base.url_encode64(token, padding: false)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded))
    end
  end

  @doc """
  Confirms a user by the given token.
  """
  @spec confirm_user(String.t()) :: {:ok, User.t()} | :error
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- confirm_user_multi(user) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  @spec confirm_user_multi(User.t()) :: {:ok, map()} | {:error, atom(), term(), map()}
  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
    |> Repo.transaction()
  end

  # --- Password Reset ---

  @doc """
  Delivers reset password instructions to the user.
  """
  @spec deliver_user_reset_password_instructions(User.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    encoded = Base.url_encode64(token, padding: false)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded))
  end

  @doc """
  Gets the user by reset password token.
  """
  @spec get_user_by_reset_password_token(String.t()) :: User.t() | nil
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.
  """
  @spec reset_user_password(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  # --- API Tokens ---

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
  Creates a new API token scoped to a company. Only owners can create tokens.
  Returns the plaintext token exactly once.

  ## Parameters
    - `user_id` — the creating user's ID (must be company owner)
    - `company_id` — the company to scope the token to
    - `attrs` — token attributes (`:name`, `:description`, `:expires_at`)

  ## Returns
    - `{:ok, %{token: String.t(), api_token: ApiToken.t()}}` on success
    - `{:error, :unauthorized}` if user is not an owner of the company
    - `{:error, Ecto.Changeset.t()}` on validation failure
  """
  @spec create_api_token(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, %{token: String.t(), api_token: ApiToken.t()}}
          | {:error, :unauthorized}
          | {:error, Ecto.Changeset.t()}
  def create_api_token(user_id, company_id, attrs) do
    if Companies.has_role?(user_id, company_id, :owner) do
      do_create_api_token(user_id, company_id, attrs)
    else
      {:error, :unauthorized}
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

    case Repo.insert(changeset) do
      {:ok, api_token} ->
        {:ok, %{token: plain_token, api_token: api_token}}

      {:error, changeset} ->
        {:error, changeset}
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
        |> Repo.update()
    end
  end

  @doc """
  Revokes an API token by ID, scoped to the given user and company.
  Only owners can revoke tokens.

  ## Returns
    - `{:ok, ApiToken.t()}` on success
    - `{:error, :unauthorized}` if user is not an owner of the company
    - `{:error, :not_found}` if the token doesn't exist for user + company
    - `{:error, Ecto.Changeset.t()}` on update failure
  """
  @spec revoke_api_token(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, ApiToken.t()}
          | {:error, :unauthorized}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def revoke_api_token(user_id, company_id, token_id) do
    if Companies.has_role?(user_id, company_id, :owner) do
      do_revoke_api_token(user_id, company_id, token_id)
    else
      {:error, :unauthorized}
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
