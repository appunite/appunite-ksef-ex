defmodule KsefHub.Accounts.ApiToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "api_tokens" do
    field :name, :string
    field :description, :string
    field :token_hash, :string
    field :token_prefix, :string
    field :last_used_at, :utc_datetime_usec
    field :request_count, :integer, default: 0
    field :is_active, :boolean, default: true

    belongs_to :created_by, KsefHub.Accounts.User

    timestamps()
  end

  def changeset(api_token, attrs) do
    api_token
    |> cast(attrs, [:name, :description, :is_active, :created_by_id])
    |> validate_required([:name])
    |> unique_constraint(:token_hash)
  end
end
