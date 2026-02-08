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
end
