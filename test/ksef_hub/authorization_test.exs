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
    :view_exports,
    :create_export,
    :manage_company,
    :delete_company,
    :transfer_ownership,
    :manage_certificates,
    :manage_tokens,
    :manage_team,
    :view_payment_requests,
    :manage_payment_requests,
    :manage_bank_accounts
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

  describe "approver" do
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
      :manage_tokens,
      :view_payment_requests,
      :manage_payment_requests
    ]

    @reviewer_denied @all_permissions -- @reviewer_allowed

    test "has allowed permissions" do
      for perm <- @reviewer_allowed do
        assert Authorization.can?(:approver, perm),
               "expected reviewer to have #{perm}"
      end
    end

    test "does not have denied permissions" do
      for perm <- @reviewer_denied do
        refute Authorization.can?(:approver, perm),
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
      :manage_tokens,
      :view_payment_requests
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

  describe "analyst" do
    @viewer_allowed [:view_invoices]

    @viewer_denied @all_permissions -- @viewer_allowed

    test "has allowed permissions" do
      for perm <- @viewer_allowed do
        assert Authorization.can?(:analyst, perm),
               "expected viewer to have #{perm}"
      end
    end

    test "does not have denied permissions" do
      for perm <- @viewer_denied do
        refute Authorization.can?(:analyst, perm),
               "expected viewer NOT to have #{perm}"
      end
    end

    test "cannot access dashboard" do
      refute Authorization.can?(:analyst, :view_dashboard)
    end

    test "cannot approve invoices" do
      refute Authorization.can?(:analyst, :approve_invoice)
    end

    test "cannot update invoices" do
      refute Authorization.can?(:analyst, :update_invoice)
    end

    test "cannot manage tokens" do
      refute Authorization.can?(:analyst, :manage_tokens)
    end

    test "cannot see all invoice types (access_restricted filter applies)" do
      refute Authorization.can?(:analyst, :view_all_invoice_types)
    end

    test "cannot access exports" do
      refute Authorization.can?(:analyst, :view_exports)
      refute Authorization.can?(:analyst, :create_export)
    end

    test "cannot access payment requests" do
      refute Authorization.can?(:analyst, :view_payment_requests)
      refute Authorization.can?(:analyst, :manage_payment_requests)
    end
  end
end
