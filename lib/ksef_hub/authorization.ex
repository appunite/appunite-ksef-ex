defmodule KsefHub.Authorization do
  @moduledoc """
  Centralized authorization module — single source of truth for all permission checks.

  Defines which roles can perform which actions. Used by API plugs, LiveView hooks,
  menu visibility, and context-level authorization.

  ## Roles

  - `:owner` — full access including destructive operations (delete company, transfer ownership)
  - `:admin` — same as owner except cannot delete company or transfer ownership
  - `:reviewer` — can view and manage expense invoices, trigger syncs
  - `:accountant` — read-only invoice access plus exports and API token management
  """

  alias KsefHub.Companies.Membership

  @type permission ::
          :view_dashboard
          | :view_invoices
          | :create_invoice
          | :update_invoice
          | :approve_invoice
          | :set_invoice_category
          | :set_invoice_tags
          | :view_syncs
          | :trigger_sync
          | :manage_categories
          | :manage_tags
          | :view_exports
          | :create_export
          | :manage_company
          | :delete_company
          | :transfer_ownership
          | :manage_certificates
          | :manage_tokens
          | :manage_team

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
  @spec can?(Membership.role(), permission()) :: boolean()
  # Owner can do everything
  def can?(:owner, _permission), do: true

  # Admin can do everything except delete company and transfer ownership
  def can?(:admin, :delete_company), do: false
  def can?(:admin, :transfer_ownership), do: false
  def can?(:admin, _permission), do: true

  # Reviewer permissions
  def can?(:reviewer, :view_dashboard), do: true
  def can?(:reviewer, :view_invoices), do: true
  def can?(:reviewer, :create_invoice), do: true
  def can?(:reviewer, :update_invoice), do: true
  def can?(:reviewer, :approve_invoice), do: true
  def can?(:reviewer, :set_invoice_category), do: true
  def can?(:reviewer, :set_invoice_tags), do: true
  def can?(:reviewer, :view_syncs), do: true
  def can?(:reviewer, :trigger_sync), do: true
  def can?(:reviewer, _permission), do: false

  # Accountant permissions
  def can?(:accountant, :view_dashboard), do: true
  def can?(:accountant, :view_invoices), do: true
  def can?(:accountant, :view_exports), do: true
  def can?(:accountant, :create_export), do: true
  def can?(:accountant, :manage_tokens), do: true
  def can?(:accountant, _permission), do: false
end
