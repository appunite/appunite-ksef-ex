defmodule KsefHub.Invoices.InvoiceTag do
  @moduledoc "Join schema linking invoices to tags."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invoice_tags" do
    belongs_to :invoice, KsefHub.Invoices.Invoice
    belongs_to :tag, KsefHub.Invoices.Tag

    timestamps()
  end

  @doc "Builds a changeset for invoice-tag association."
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(invoice_tag, attrs) do
    invoice_tag
    |> cast(attrs, [:invoice_id, :tag_id])
    |> validate_required([:invoice_id, :tag_id])
    |> unique_constraint([:invoice_id, :tag_id])
    |> foreign_key_constraint(:invoice_id)
    |> foreign_key_constraint(:tag_id)
  end
end
