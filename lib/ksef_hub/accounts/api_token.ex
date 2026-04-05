defmodule KsefHub.Accounts.ApiToken do
  @moduledoc """
  API token schema. Tokens authenticate external API consumers.

  Each token is scoped to a single company — the company is derived from the
  token during API authentication, so consumers never need to pass a company_id
  parameter.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @behaviour KsefHub.ActivityLog.Trackable

  @type t :: %__MODULE__{}

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
    field :expires_at, :utc_datetime_usec

    belongs_to :created_by, KsefHub.Accounts.User
    belongs_to :company, KsefHub.Companies.Company

    timestamps()
  end

  @doc "Builds a changeset for token creation/update."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(api_token, attrs) do
    api_token
    |> cast(attrs, [:name, :description, :is_active, :expires_at])
    |> validate_required([:name])
    |> unique_constraint(:token_hash)
  end

  @impl KsefHub.ActivityLog.Trackable
  @spec track_change(Ecto.Changeset.t()) :: {String.t(), map()} | :skip
  def track_change(%Ecto.Changeset{action: :insert} = cs) do
    {"api_token.generated", %{token_name: get_field(cs, :name)}}
  end

  def track_change(%Ecto.Changeset{} = cs) do
    case cs.changes do
      %{is_active: false} -> {"api_token.revoked", %{token_name: cs.data.name}}
      _ -> :skip
    end
  end

  @impl KsefHub.ActivityLog.Trackable
  @spec track_delete(t()) :: :skip
  def track_delete(_token), do: :skip
end
