defmodule KsefHub.Invitations.Invitation do
  @moduledoc """
  Invitation schema. Represents an invitation for a user to join a company.

  Roles that can be invited:
  - `accountant` — can view invoices, manage bookkeeping, and submit expense approvals
  - `invoice_reviewer` — can view invoices and approve or reject individual expense items

  The `owner` role cannot be invited — ownership is assigned only at company creation.

  Invitation statuses:
  - `pending` — waiting for the invitee to accept
  - `accepted` — invitee accepted and membership was created
  - `cancelled` — owner cancelled the invitation before acceptance
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @invitable_roles ~w(accountant invoice_reviewer)
  @statuses ~w(pending accepted cancelled)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invitations" do
    field :email, :string
    field :role, :string
    field :token_hash, :string
    field :status, :string, default: "pending"
    field :expires_at, :utc_datetime

    belongs_to :company, KsefHub.Companies.Company
    belongs_to :invited_by, KsefHub.Accounts.User

    timestamps()
  end

  @doc "Returns the list of roles that can be invited."
  @spec invitable_roles() :: [String.t()]
  def invitable_roles, do: @invitable_roles

  @doc "Returns the list of valid invitation statuses."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc """
  Builds a changeset for invitation creation/update.

  The `company_id`, `invited_by_id`, and `token_hash` must be set directly
  on the struct before calling this function to prevent mass-assignment.
  Only `:email`, `:role`, `:status`, and `:expires_at` are cast from attrs.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :role, :status, :expires_at])
    |> validate_required([
      :email,
      :role,
      :status,
      :expires_at,
      :company_id,
      :invited_by_id,
      :token_hash
    ])
    |> validate_inclusion(:role, @invitable_roles)
    |> validate_inclusion(:status, @statuses)
    |> validate_email()
    |> normalize_email()
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:invited_by_id)
    |> unique_constraint(:email,
      name: :invitations_company_id_email_pending_index,
      message: "already has a pending invitation for this company"
    )
    |> unique_constraint(:token_hash,
      name: :invitations_token_hash_index,
      message: "token already exists"
    )
  end

  @spec validate_email(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "must be a valid email address"
    )
  end

  @spec normalize_email(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp normalize_email(changeset) do
    case get_change(changeset, :email) do
      nil -> changeset
      email -> put_change(changeset, :email, String.downcase(String.trim(email)))
    end
  end
end
