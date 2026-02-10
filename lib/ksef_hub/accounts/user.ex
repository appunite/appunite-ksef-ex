defmodule KsefHub.Accounts.User do
  @moduledoc """
  User schema.

  Supports both Google OAuth users (via `google_uid`) and email/password
  users (via `hashed_password`). Google-only users have a nil `hashed_password`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :name, :string
    field :google_uid, :string
    field :avatar_url, :string
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :password, :string, virtual: true, redact: true

    has_many :api_tokens, KsefHub.Accounts.ApiToken, foreign_key: :created_by_id

    timestamps()
  end

  @doc "Builds a changeset for Google OAuth user creation/update."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :google_uid, :avatar_url])
    |> update_change(:email, fn v -> if is_binary(v), do: String.downcase(v), else: v end)
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> unique_constraint(:email)
    |> unique_constraint(:google_uid)
  end

  @doc """
  Builds a changeset for email/password registration.

  Validates email format, password length (12-72 chars), and hashes the
  password with bcrypt.
  """
  @spec registration_changeset(t(), map(), keyword()) :: Ecto.Changeset.t()
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_email(opts)
    |> validate_password(opts)
  end

  @doc """
  Builds a changeset for changing the password.

  Validates length and hashes with bcrypt.
  """
  @spec password_changeset(t(), map(), keyword()) :: Ecto.Changeset.t()
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_password(opts)
  end

  @doc """
  Confirms the user by setting `confirmed_at` to the current time.
  """
  @spec confirm_changeset(t()) :: Ecto.Changeset.t()
  def confirm_changeset(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies a password against the user's hashed password.

  Returns `false` if the user has no hashed password (Google-only user)
  to prevent timing attacks while still rejecting the attempt.
  """
  @spec valid_password?(t(), String.t()) :: boolean()
  def valid_password?(%__MODULE__{hashed_password: hashed} = _user, password)
      when is_binary(hashed) and is_binary(password) do
    Bcrypt.verify_pass(password, hashed)
  end

  def valid_password?(_user, _password) do
    Bcrypt.no_user_verify()
    false
  end

  @spec validate_email(Ecto.Changeset.t(), keyword()) :: Ecto.Changeset.t()
  defp validate_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
      |> validate_length(:email, max: 160)
      |> update_change(:email, fn email ->
        email |> String.downcase() |> String.trim()
      end)
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  @spec validate_password(Ecto.Changeset.t(), keyword()) :: Ecto.Changeset.t()
  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  @spec maybe_hash_password(Ecto.Changeset.t(), keyword()) :: Ecto.Changeset.t()
  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end
end
