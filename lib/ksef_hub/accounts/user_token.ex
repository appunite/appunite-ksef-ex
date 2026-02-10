defmodule KsefHub.Accounts.UserToken do
  @moduledoc """
  Schema and functions for managing user session and email tokens.

  Session tokens are stored as SHA256 hashes in the database, with the raw
  token kept only in the user's session cookie. Email tokens (confirmation,
  password reset) are base64-encoded for URL safety.
  """

  use Ecto.Schema

  import Ecto.Query

  @type t :: %__MODULE__{}

  @rand_size 32

  # Token validity periods
  @session_validity_in_days 60
  @confirm_validity_in_days 3
  @reset_password_validity_in_days 1

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string

    belongs_to :user, KsefHub.Accounts.User

    timestamps(updated_at: false)
  end

  @doc """
  Generates a session token and its hashed counterpart for storage.

  Returns `{raw_token, %UserToken{}}` where `raw_token` is the 32-byte
  binary to store in the session cookie, and the struct contains the
  SHA256 hash for database storage.
  """
  @spec build_session_token(KsefHub.Accounts.User.t()) :: {binary(), t()}
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {token,
     %__MODULE__{token: :crypto.hash(:sha256, token), context: "session", user_id: user.id}}
  end

  @doc """
  Checks if the session token is valid and returns a query to fetch the user.

  The token is valid if it matches an existing token in the database and has
  not expired (60 days).
  """
  @spec verify_session_token_query(binary()) :: {:ok, Ecto.Query.t()}
  def verify_session_token_query(token) do
    hashed_token = :crypto.hash(:sha256, token)

    query =
      from token in by_token_and_context_query(hashed_token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: user

    {:ok, query}
  end

  @doc """
  Builds an email token for the given user and context.

  The raw token is stored in the struct for hashing; the encoded version
  is returned for inclusion in email URLs.
  """
  @spec build_email_token(KsefHub.Accounts.User.t(), String.t()) :: {binary(), t()}
  def build_email_token(user, context) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {token,
     %__MODULE__{
       token: :crypto.hash(:sha256, token),
       context: context,
       sent_to: user.email,
       user_id: user.id
     }}
  end

  @doc """
  Checks if the email token is valid and returns a query to fetch the user.

  The token must be base64-decoded, then SHA256-hashed to match the database.
  Validity depends on context: 3 days for confirm, 1 day for reset_password.
  """
  @spec verify_email_token_query(String.t(), String.t()) :: {:ok, Ecto.Query.t()} | :error
  def verify_email_token_query(encoded_token, context) do
    with {:ok, decoded_token} <- Base.url_decode64(encoded_token, padding: false),
         {:ok, days} <- days_for_context(context) do
      hashed_token = :crypto.hash(:sha256, decoded_token)

      query =
        from token in by_token_and_context_query(hashed_token, context),
          join: user in assoc(token, :user),
          where: token.inserted_at > ago(^days, "day") and token.sent_to == user.email,
          select: user

      {:ok, query}
    else
      _ -> :error
    end
  end

  @doc """
  Returns a query that finds all tokens for a user in the given contexts.

  Pass `:all` to match all contexts.
  """
  @spec by_user_and_contexts_query(KsefHub.Accounts.User.t(), :all | [String.t()]) ::
          Ecto.Query.t()
  def by_user_and_contexts_query(user, :all) do
    from t in __MODULE__, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, contexts) when is_list(contexts) do
    from t in __MODULE__, where: t.user_id == ^user.id and t.context in ^contexts
  end

  @spec by_token_and_context_query(binary(), String.t()) :: Ecto.Query.t()
  defp by_token_and_context_query(token, context) do
    from __MODULE__, where: [token: ^token, context: ^context]
  end

  @spec days_for_context(String.t()) :: {:ok, pos_integer()} | :error
  defp days_for_context("confirm"), do: {:ok, @confirm_validity_in_days}
  defp days_for_context("reset_password"), do: {:ok, @reset_password_validity_in_days}
  defp days_for_context(_), do: :error
end
