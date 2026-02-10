defmodule KsefHub.Companies.Membership do
  @moduledoc """
  Membership schema. Links a user to a company with a specific role.

  Roles:
  - `owner` — full access including certificates, API tokens, team management
  - `accountant` — can view invoices and approve/reject expenses
  - `invoice_reviewer` — can view invoices and approve/reject expenses
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @roles ~w(owner accountant invoice_reviewer)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "memberships" do
    field :role, :string

    belongs_to :user, KsefHub.Accounts.User
    belongs_to :company, KsefHub.Companies.Company

    timestamps()
  end

  @doc "Returns the list of valid membership roles."
  @spec roles() :: [String.t()]
  def roles, do: @roles

  @doc "Builds a changeset for membership creation/update."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:user_id, :company_id, :role])
    |> validate_required([:user_id, :company_id, :role])
    |> validate_inclusion(:role, @roles)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:company_id)
    |> unique_constraint([:user_id, :company_id],
      name: :memberships_user_id_company_id_index,
      message: "already a member of this company"
    )
  end
end
