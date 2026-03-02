defmodule KsefHub.Invoices.InvoiceComment do
  @moduledoc "Schema for comments on invoices with user attribution."

  use Ecto.Schema
  import Ecto.Changeset

  alias KsefHub.Accounts.User
  alias KsefHub.Invoices.Invoice

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invoice_comments" do
    field :body, :string

    belongs_to :invoice, Invoice
    belongs_to :user, User

    timestamps()
  end

  @doc "Builds a changeset for creating or updating a comment."
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body])
    |> validate_required([:body])
    |> validate_length(:body, max: 10_000)
    |> foreign_key_constraint(:invoice_id)
    |> foreign_key_constraint(:user_id)
  end
end
