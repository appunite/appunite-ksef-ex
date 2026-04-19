defmodule KsefHub.Authorization do
  @moduledoc """
  Centralized authorization module — single source of truth for all permission checks.

  Defines which roles can perform which actions. Used by API plugs, LiveView hooks,
  menu visibility, and context-level authorization.

  ## Roles

  - `:owner` — full access including destructive operations (delete company, transfer ownership)
  - `:admin` — same as owner except cannot delete company or transfer ownership
  - `:approver` — manages expense invoice workflow: approve/reject, trigger syncs, own API tokens
  - `:accountant` — read-only access to all invoice types plus exports
  - `:analyst` — read-only access to invoices; same data scope as approver, no management actions
  """

  alias KsefHub.Companies
  alias KsefHub.Companies.Membership

  @type permission ::
          :view_dashboard
          | :view_invoices
          | :view_all_invoice_types
          | :create_invoice
          | :update_invoice
          | :approve_invoice
          | :set_invoice_category
          | :set_invoice_tags
          | :view_syncs
          | :trigger_sync
          | :manage_categories
          | :view_exports
          | :create_export
          | :manage_company
          | :delete_company
          | :transfer_ownership
          | :manage_certificates
          | :manage_tokens
          | :manage_team
          | :view_payment_requests
          | :manage_payment_requests
          | :manage_bank_accounts

  @admin_denied MapSet.new([:delete_company, :transfer_ownership])

  @approver_permissions MapSet.new([
                          :view_dashboard,
                          :view_invoices,
                          :create_invoice,
                          :update_invoice,
                          :approve_invoice,
                          :set_invoice_category,
                          :set_invoice_tags,
                          :view_syncs,
                          :trigger_sync,
                          :manage_tokens,
                          :view_payment_requests,
                          :manage_payment_requests
                        ])

  @accountant_permissions MapSet.new([
                            :view_dashboard,
                            :view_invoices,
                            :view_all_invoice_types,
                            :view_exports,
                            :create_export,
                            :manage_tokens,
                            :view_payment_requests
                          ])

  @analyst_permissions MapSet.new([:view_invoices])

  @doc """
  Checks whether the given role has the specified permission.

  ## Examples

      iex> KsefHub.Authorization.can?(:owner, :delete_company)
      true

      iex> KsefHub.Authorization.can?(:admin, :delete_company)
      false

      iex> KsefHub.Authorization.can?(:accountant, :view_exports)
      true
  """
  @spec can?(Membership.role() | nil, permission()) :: boolean()
  def can?(nil, _permission), do: false
  def can?(:owner, _permission), do: true
  def can?(:admin, permission), do: permission not in @admin_denied
  def can?(:approver, permission), do: permission in @approver_permissions
  def can?(:accountant, permission), do: permission in @accountant_permissions
  def can?(:analyst, permission), do: permission in @analyst_permissions

  @doc """
  Checks whether a user has the specified permission for a company,
  by looking up their membership role.

  ## Examples

      iex> KsefHub.Authorization.can?(user_id, company_id, :manage_tokens)
      true
  """
  @spec can?(Ecto.UUID.t(), Ecto.UUID.t(), permission()) :: boolean()
  def can?(user_id, company_id, permission) when is_binary(user_id) and is_binary(company_id) do
    case Companies.get_membership(user_id, company_id) do
      %{role: role} -> can?(role, permission)
      nil -> false
    end
  end
end
