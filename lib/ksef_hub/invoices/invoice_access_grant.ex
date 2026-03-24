defmodule KsefHub.Invoices.InvoiceAccessGrant do
  @moduledoc "Schema for access grants on restricted invoices. Links a user to an invoice they are allowed to see."

  use Ecto.Schema

  alias KsefHub.Accounts.User
  alias KsefHub.Invoices.Invoice

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invoice_access_grants" do
    belongs_to :invoice, Invoice
    belongs_to :user, User
    belongs_to :granted_by, User

    timestamps()
  end
end
