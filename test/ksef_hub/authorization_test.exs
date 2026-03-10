defmodule KsefHub.AuthorizationTest do
  use ExUnit.Case, async: true

  alias KsefHub.Authorization

  @all_permissions [
    :view_dashboard,
    :view_invoices,
    :view_all_invoice_types,
    :create_invoice,
    :update_invoice,
    :approve_invoice,
    :set_invoice_category,
    :set_invoice_tags,
    :view_syncs,
    :trigger_sync,
    :manage_categories,
    :manage_tags,
    :view_exports,
    :create_export,
    :manage_company,
    :delete_company,
    :transfer_ownership,
    :manage_certificates,
    :manage_tokens,
    :manage_team
  ]

  describe "nil role" do
    test "has no permissions" do
      for perm <- @all_permissions do
        refute Authorization.can?(nil, perm),
               "expected nil role NOT to have #{perm}"
      end
    end
  end

  describe "owner" do
    test "has all permissions" do
      for perm <- @all_permissions do
        assert Authorization.can?(:owner, perm),
               "expected owner to have #{perm}"
      end
    end
  end

  describe "admin" do
    test "has all permissions except delete_company and transfer_ownership" do
      for perm <- @all_permissions -- [:delete_company, :transfer_ownership] do
        assert Authorization.can?(:admin, perm),
               "expected admin to have #{perm}"
      end
    end

    test "cannot delete company" do
      refute Authorization.can?(:admin, :delete_company)
    end

    test "cannot transfer ownership" do
      refute Authorization.can?(:admin, :transfer_ownership)
    end
  end

  describe "reviewer" do
    @reviewer_allowed [
      :view_dashboard,
      :view_invoices,
      :create_invoice,
      :update_invoice,
      :approve_invoice,
      :set_invoice_category,
      :set_invoice_tags,
      :view_syncs,
      :trigger_sync,
      :manage_tokens
    ]

    @reviewer_denied @all_permissions -- @reviewer_allowed

    test "has allowed permissions" do
      for perm <- @reviewer_allowed do
        assert Authorization.can?(:reviewer, perm),
               "expected reviewer to have #{perm}"
      end
    end

    test "does not have denied permissions" do
      for perm <- @reviewer_denied do
        refute Authorization.can?(:reviewer, perm),
               "expected reviewer NOT to have #{perm}"
      end
    end
  end

  describe "accountant" do
    @accountant_allowed [
      :view_dashboard,
      :view_invoices,
      :view_all_invoice_types,
      :view_exports,
      :create_export,
      :manage_tokens
    ]

    @accountant_denied @all_permissions -- @accountant_allowed

    test "has allowed permissions" do
      for perm <- @accountant_allowed do
        assert Authorization.can?(:accountant, perm),
               "expected accountant to have #{perm}"
      end
    end

    test "does not have denied permissions" do
      for perm <- @accountant_denied do
        refute Authorization.can?(:accountant, perm),
               "expected accountant NOT to have #{perm}"
      end
    end
  end
end
