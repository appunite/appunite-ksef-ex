defmodule KsefHub.Invoices.InvoiceAccessGrant do
  @moduledoc "Schema for access grants on restricted invoices. Links a user to an invoice they are allowed to see."

  use Ecto.Schema
  import Ecto.Changeset

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

  @doc "Builds a changeset for creating an access grant."
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(grant, attrs) do
    grant
    |> cast(attrs, [:invoice_id, :user_id, :granted_by_id])
    |> validate_required([:invoice_id, :user_id])
    |> unique_constraint([:invoice_id, :user_id])
    |> foreign_key_constraint(:invoice_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:granted_by_id)
  end
end
