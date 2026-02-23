defmodule KsefHub.Invoices.Tag do
  @moduledoc "Tag schema. Provides flexible multi-label annotation for invoices."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tags" do
    field :name, :string
    field :description, :string
    field :usage_count, :integer, virtual: true, default: 0

    belongs_to :company, KsefHub.Companies.Company
    many_to_many :invoices, KsefHub.Invoices.Invoice, join_through: "invoice_tags"

    timestamps()
  end

  @doc "Builds a changeset for tag creation/update."
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :description])
    |> validate_required([:name, :company_id])
    |> unique_constraint([:company_id, :name])
    |> foreign_key_constraint(:company_id)
  end
end
