defmodule KsefHub.Exports.InvoiceDownload do
  @moduledoc "Schema for tracking which invoices were included in each export batch per user."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invoice_downloads" do
    field :downloaded_at, :utc_datetime_usec

    belongs_to :invoice, KsefHub.Invoices.Invoice
    belongs_to :export_batch, KsefHub.Exports.ExportBatch
    belongs_to :user, KsefHub.Accounts.User
  end

  @doc "Builds a changeset for creating an invoice download record."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(download, attrs) do
    download
    |> cast(attrs, [:downloaded_at])
    |> validate_required([:downloaded_at])
    |> foreign_key_constraint(:invoice_id)
    |> foreign_key_constraint(:export_batch_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:invoice_id, :export_batch_id])
  end
end
