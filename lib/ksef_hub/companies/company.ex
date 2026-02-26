defmodule KsefHub.Companies.Company do
  @moduledoc "Company schema. Represents a business entity identified by NIP."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "companies" do
    field :name, :string
    field :nip, :string
    field :address, :string
    field :is_active, :boolean, default: true
    field :inbound_email_token_hash, :string
    field :has_active_credential, :boolean, virtual: true

    timestamps()
  end

  @doc "Builds a changeset for company creation/update."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(company, attrs) do
    company
    |> cast(attrs, [:name, :nip, :address, :is_active])
    |> validate_required([:name, :nip])
    |> validate_format(:nip, ~r/^\d{10}$/, message: "must be a 10-digit NIP")
    |> unique_constraint(:nip)
  end

  @doc "Builds a changeset for setting or clearing the inbound email token hash."
  @spec inbound_email_token_hash_changeset(t(), String.t() | nil) :: Ecto.Changeset.t()
  def inbound_email_token_hash_changeset(company, token_hash) do
    company
    |> change(%{inbound_email_token_hash: token_hash})
    |> unique_constraint(:inbound_email_token_hash,
      name: :companies_inbound_email_token_hash_unique
    )
  end
end
