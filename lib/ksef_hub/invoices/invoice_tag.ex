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

  @doc "Builds a changeset for an invoice-tag association with server-set FKs."
  @spec changeset(Ecto.UUID.t(), Ecto.UUID.t()) :: Ecto.Changeset.t()
  def changeset(invoice_id, tag_id) do
    %__MODULE__{}
    |> change(%{invoice_id: invoice_id, tag_id: tag_id})
    |> unique_constraint([:invoice_id, :tag_id])
    |> foreign_key_constraint(:invoice_id)
    |> foreign_key_constraint(:tag_id)
  end
end
