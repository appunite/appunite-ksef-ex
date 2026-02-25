defmodule KsefHub.Invoices.Category do
  @moduledoc "Category schema. Provides single-label classification for invoices with `group:target` naming."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "categories" do
    field :name, :string
    field :emoji, :string
    field :description, :string
    field :sort_order, :integer, default: 0

    belongs_to :company, KsefHub.Companies.Company
    has_many :invoices, KsefHub.Invoices.Invoice

    timestamps()
  end

  @doc "Builds a changeset for category creation/update."
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :emoji, :description, :sort_order])
    |> validate_required([:name, :company_id])
    |> validate_format(:name, ~r/^[^:]+:.+$/, message: "must be in group:target format")
    |> unique_constraint([:company_id, :name], error_key: :name)
    |> foreign_key_constraint(:company_id)
  end
end
