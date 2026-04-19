defmodule KsefHub.Companies.Membership do
  @moduledoc """
  Membership schema. Links a user to a company with a specific role and status.

  ## Roles

  - `:owner` — full access including destructive operations (delete company, transfer ownership)
  - `:admin` — same as owner except cannot delete company or transfer ownership
  - `:accountant` — read-only invoice access plus exports and API token management
  - `:approver` — manages expense invoice workflow: approve/reject, trigger syncs, own API tokens
  - `:analyst` — read-only access to invoices; same data scope as approver, no management actions

  ## Status

  - `:active` — normal access (default)
  - `:blocked` — soft-deleted; member loses all access without destroying the record
  """

  use Ecto.Schema
  import Ecto.Changeset

  @behaviour KsefHub.ActivityLog.Trackable

  @type t :: %__MODULE__{}
  @type role :: :owner | :admin | :accountant | :approver | :analyst
  @type status :: :active | :blocked

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "memberships" do
    field :role, Ecto.Enum, values: [:owner, :admin, :accountant, :approver, :analyst]
    field :status, Ecto.Enum, values: [:active, :blocked], default: :active

    belongs_to :user, KsefHub.Accounts.User
    belongs_to :company, KsefHub.Companies.Company

    timestamps()
  end

  @doc "Returns the list of valid membership roles."
  @spec roles() :: [role()]
  def roles, do: Ecto.Enum.values(__MODULE__, :role)

  @doc "Returns a human-readable label for a role."
  @spec role_label(role()) :: String.t()
  def role_label(role), do: role |> Atom.to_string() |> String.capitalize()

  @doc "Returns a short description of what a role can do."
  @spec role_description(role()) :: String.t()
  def role_description(:owner),
    do: "Full access including destructive operations like deleting the company."

  def role_description(:admin),
    do: "Same as Owner, except cannot delete the company or transfer ownership."

  def role_description(:approver),
    do:
      "Can view and manage expense invoices, approve/reject, trigger syncs, and manage payment requests."

  def role_description(:accountant),
    do: "Read-only invoice access for all types, plus exports and API token management."

  def role_description(:analyst),
    do:
      "Read-only access to invoices. Same data scope as approver — use invoice grants for restricted invoices. No dashboard, exports, payments, or other features."

  def role_description(_), do: ""

  @doc "Returns the roles that the given role is allowed to assign to other members."
  @spec assignable_roles(role()) :: [role()]
  def assignable_roles(:owner), do: [:admin, :accountant, :approver, :analyst]
  def assignable_roles(:admin), do: [:admin, :accountant, :approver, :analyst]
  def assignable_roles(_), do: []

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

  @doc "Builds a changeset for status-only updates (block/unblock)."
  @spec status_changeset(t(), map()) :: Ecto.Changeset.t()
  def status_changeset(membership, attrs) do
    membership
    |> cast(attrs, [:status])
    |> validate_required([:status])
  end

  # ---------------------------------------------------------------------------
  # Trackable
  # ---------------------------------------------------------------------------

  @impl KsefHub.ActivityLog.Trackable
  @spec track_change(Ecto.Changeset.t()) :: {String.t(), map()} | :skip
  def track_change(%Ecto.Changeset{} = cs) do
    changes = cs.changes

    cond do
      Map.has_key?(changes, :role) ->
        {"team.role_changed",
         %{
           member_user_id: cs.data.user_id,
           old_role: to_string(cs.data.role),
           new_role: to_string(changes.role)
         }}

      Map.has_key?(changes, :status) ->
        action =
          if changes.status == :blocked, do: "team.member_blocked", else: "team.member_unblocked"

        {action, %{member_user_id: cs.data.user_id}}

      true ->
        :skip
    end
  end

  @impl KsefHub.ActivityLog.Trackable
  @spec track_delete(t()) :: {String.t(), map()}
  def track_delete(%__MODULE__{} = m) do
    {"team.member_removed", %{member_user_id: m.user_id}}
  end
end
