defmodule KsefHub.Invoices.InvoicePublicToken do
  @moduledoc """
  Per-user shareable token for public invoice access.

  Each token is scoped to a single (invoice, user) pair and expires after 30 days.
  Multiple valid tokens may exist for the same invoice if shared by different users.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias KsefHub.Accounts.User
  alias KsefHub.Invoices.Invoice

  @type t :: %__MODULE__{}

  @derive {Inspect, except: [:token]}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invoice_public_tokens" do
    field :token, :string
    field :expires_at, :utc_datetime

    belongs_to :invoice, Invoice
    belongs_to :user, User

    timestamps(updated_at: false)
  end

  @doc """
  Builds a changeset for inserting a new public token.

  Only `:token` and `:expires_at` are cast from attrs. The `invoice_id` and
  `user_id` must be set directly on the struct before calling this function to
  prevent mass-assignment of foreign keys from user input.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(token_record, attrs) do
    token_record
    |> cast(attrs, [:token, :expires_at])
    |> validate_required([:token, :expires_at, :invoice_id, :user_id])
    |> foreign_key_constraint(:invoice_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:token)
  end
end
