defmodule KsefHub.Accounts do
  @moduledoc """
  The Accounts context. Manages users and API tokens.
  """

  import Ecto.Query
  alias KsefHub.Repo
  alias KsefHub.Accounts.{User, ApiToken}

  @token_bytes 32

  # --- Users ---

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email), do: Repo.get_by(User, email: email)

  def get_user_by_google_uid(uid), do: Repo.get_by(User, google_uid: uid)

  @doc """
  Finds a user by Google UID, or creates one from Google auth info.
  Returns `{:ok, user}` or `{:error, changeset}`.
  """
  def find_or_create_user(%{uid: uid, email: email} = info) do
    case get_user_by_google_uid(uid) do
      nil ->
        %User{}
        |> User.changeset(%{
          google_uid: uid,
          email: email,
          name: Map.get(info, :name),
          avatar_url: Map.get(info, :avatar_url)
        })
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end

  @doc """
  Checks if an email is in the allowlist.
  """
  def allowed_email?(email) do
    allowed =
      Application.get_env(:ksef_hub, :allowed_emails, "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.downcase/1)

    String.downcase(email) in allowed
  end

  # --- API Tokens ---

  @doc """
  Creates a new API token. Returns the plaintext token exactly once.
  """
  def create_api_token(attrs) do
    plain_token = generate_token()
    token_hash = hash_token(plain_token)
    token_prefix = String.slice(plain_token, 0, 8)

    attrs =
      attrs
      |> Map.put(:token_hash, token_hash)
      |> Map.put(:token_prefix, token_prefix)

    case %ApiToken{} |> ApiToken.changeset(attrs) |> Repo.insert() do
      {:ok, api_token} ->
        {:ok, %{token: plain_token, api_token: api_token}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Validates a plaintext API token. Returns the token record if valid.
  """
  def validate_api_token(plain_token) do
    token_hash = hash_token(plain_token)

    case Repo.get_by(ApiToken, token_hash: token_hash, is_active: true) do
      nil -> {:error, :invalid}
      api_token -> {:ok, api_token}
    end
  end

  @doc """
  Revokes an API token by ID.
  """
  def revoke_api_token(token_id) do
    case Repo.get(ApiToken, token_id) do
      nil ->
        {:error, :not_found}

      api_token ->
        api_token
        |> ApiToken.changeset(%{is_active: false})
        |> Repo.update()
    end
  end

  @doc """
  Lists all API tokens (without revealing hashes).
  """
  def list_api_tokens do
    ApiToken
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  @doc """
  Tracks usage of an API token (last_used_at, request_count).
  """
  def track_token_usage(token_id) do
    {1, _} =
      from(t in ApiToken, where: t.id == ^token_id)
      |> Repo.update_all(
        set: [last_used_at: DateTime.utc_now()],
        inc: [request_count: 1]
      )

    :ok
  end

  defp generate_token do
    @token_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp hash_token(token) do
    :crypto.hash(:sha256, token)
    |> Base.encode16(case: :lower)
  end
end
