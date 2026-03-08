defmodule KsefHub.Companies.Membership do
  @moduledoc """
  Membership schema. Links a user to a company with a specific role.

  Roles:
  - `owner` — full access including destructive operations (delete company, transfer ownership)
  - `admin` — same as owner except cannot delete company or transfer ownership
  - `accountant` — read-only invoice access plus exports and API token management
  - `reviewer` — can view and manage expense invoices, trigger syncs
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @type role :: :owner | :admin | :accountant | :reviewer

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "memberships" do
    field :role, Ecto.Enum, values: [:owner, :admin, :accountant, :reviewer]

    belongs_to :user, KsefHub.Accounts.User
    belongs_to :company, KsefHub.Companies.Company

    timestamps()
  end

  @doc "Returns the list of valid membership roles."
  @spec roles() :: [role()]
  def roles, do: Ecto.Enum.values(__MODULE__, :role)

  @doc """
  Builds a changeset for membership creation/update.

  Only `:role` is cast from attrs. The `user_id` and `company_id` must be set
  directly on the struct before calling this function to prevent mass-assignment
  of foreign keys from user input.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role])
    |> validate_required([:user_id, :company_id, :role])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:company_id)
    |> unique_constraint([:user_id, :company_id],
      name: :memberships_user_id_company_id_index,
      message: "already a member of this company"
    )
  end
end
