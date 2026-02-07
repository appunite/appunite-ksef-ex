defmodule KsefHub.Accounts.User do
  @moduledoc "User schema."

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

    has_many :api_tokens, KsefHub.Accounts.ApiToken, foreign_key: :created_by_id

    timestamps()
  end

  @doc "Builds a changeset for user creation/update."
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
end
