defmodule KsefHub.Invoices.Category do
  @moduledoc "Category schema. Provides single-label classification for invoices with `group:target` naming."

  use Ecto.Schema
  import Ecto.Changeset

  alias KsefHub.Invoices.CostLine

  @behaviour KsefHub.ActivityLog.Trackable

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "categories" do
    field :identifier, :string
    field :name, :string
    field :emoji, :string
    field :description, :string
    field :examples, :string
    field :sort_order, :integer, default: 0
    field :default_cost_line, Ecto.Enum, values: CostLine.values()

    belongs_to :company, KsefHub.Companies.Company
    has_many :invoices, KsefHub.Invoices.Invoice, foreign_key: :expense_category_id

    timestamps()
  end

  @doc "Builds a changeset for category creation/update."
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(category, attrs) do
    category
    |> cast(attrs, [
      :identifier,
      :name,
      :emoji,
      :description,
      :examples,
      :sort_order,
      :default_cost_line
    ])
    |> validate_required([:identifier, :company_id])
    |> validate_format(:identifier, ~r/^[^:]+:.+$/, message: "must be in group:target format")
    |> unique_constraint([:company_id, :identifier], error_key: :identifier)
    |> foreign_key_constraint(:company_id)
  end

  @impl KsefHub.ActivityLog.Trackable
  @spec track_change(Ecto.Changeset.t()) :: {String.t(), map()}
  def track_change(%Ecto.Changeset{action: :insert} = cs) do
    {"category.created", %{name: get_change(cs, :name), identifier: get_change(cs, :identifier)}}
  end

  def track_change(%Ecto.Changeset{} = cs) do
    {"category.updated", %{name: cs.data.name || get_change(cs, :name)}}
  end

  @impl KsefHub.ActivityLog.Trackable
  @spec track_delete(t()) :: {String.t(), map()}
  def track_delete(category) do
    {"category.deleted", %{name: category.name, identifier: category.identifier}}
  end
end
