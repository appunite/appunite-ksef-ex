defmodule KsefHub.Invoices.AutoApprovalTest do
  @moduledoc "Tests for AutoApproval: decides whether invoices should be auto-approved."

  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invoices.AutoApproval

  setup do
    company = insert(:company, auto_approve_trusted_invoices: true)
    %{company: company}
  end

  defp build_invoice(attrs) do
    defaults = %{
      type: :expense,
      source: :manual,
      extraction_status: :complete,
      status: :pending
    }

    struct!(KsefHub.Invoices.Invoice, Map.merge(defaults, attrs))
  end

  describe "should_auto_approve?/3 — feature toggle" do
    test "returns false when company has auto_approve_trusted_invoices disabled" do
      company = insert(:company, auto_approve_trusted_invoices: false)
      invoice = build_invoice(%{source: :manual})

      refute AutoApproval.should_auto_approve?(company, invoice)
    end
  end

  describe "should_auto_approve?/3 — invoice type" do
    test "returns false for income invoices", %{company: company} do
      invoice = build_invoice(%{type: :income, source: :manual})

      refute AutoApproval.should_auto_approve?(company, invoice)
    end
  end

  describe "should_auto_approve?/3 — extraction status" do
    test "returns false for partial extraction", %{company: company} do
      invoice = build_invoice(%{extraction_status: :partial})

      refute AutoApproval.should_auto_approve?(company, invoice)
    end

    test "returns false for failed extraction", %{company: company} do
      invoice = build_invoice(%{extraction_status: :failed})

      refute AutoApproval.should_auto_approve?(company, invoice)
    end
  end

  describe "should_auto_approve?/3 — source: ksef" do
    test "returns false for KSeF invoices", %{company: company} do
      invoice = build_invoice(%{source: :ksef})

      refute AutoApproval.should_auto_approve?(company, invoice)
    end
  end

  describe "should_auto_approve?/3 — source: manual" do
    test "returns true for manual invoices with complete extraction", %{company: company} do
      invoice = build_invoice(%{source: :manual, extraction_status: :complete})

      assert AutoApproval.should_auto_approve?(company, invoice)
    end
  end

  describe "should_auto_approve?/3 — source: pdf_upload" do
    test "returns true for PDF upload invoices with complete extraction", %{company: company} do
      invoice = build_invoice(%{source: :pdf_upload, extraction_status: :complete})

      assert AutoApproval.should_auto_approve?(company, invoice)
    end
  end

  describe "should_auto_approve?/3 — source: email" do
    test "returns true when sender is an active company member", %{company: company} do
      user = insert(:user, email: "member@appunite.com")
      insert(:membership, user: user, company: company, status: :active)
      invoice = build_invoice(%{source: :email})

      assert AutoApproval.should_auto_approve?(company, invoice,
               sender_email: "member@appunite.com"
             )
    end

    test "returns false when sender has no platform account", %{company: company} do
      invoice = build_invoice(%{source: :email})

      refute AutoApproval.should_auto_approve?(company, invoice,
               sender_email: "stranger@example.com"
             )
    end

    test "returns false when sender is a platform user but not a member of this company", %{
      company: company
    } do
      user = insert(:user, email: "other@appunite.com")
      other_company = insert(:company)
      insert(:membership, user: user, company: other_company, status: :active)
      invoice = build_invoice(%{source: :email})

      refute AutoApproval.should_auto_approve?(company, invoice,
               sender_email: "other@appunite.com"
             )
    end

    test "returns false when sender is a blocked member", %{company: company} do
      user = insert(:user, email: "blocked@appunite.com")
      insert(:membership, user: user, company: company, status: :blocked)
      invoice = build_invoice(%{source: :email})

      refute AutoApproval.should_auto_approve?(company, invoice,
               sender_email: "blocked@appunite.com"
             )
    end

    test "returns false when sender_email is nil", %{company: company} do
      invoice = build_invoice(%{source: :email})

      refute AutoApproval.should_auto_approve?(company, invoice, sender_email: nil)
    end

    test "returns false when sender_email is not provided", %{company: company} do
      invoice = build_invoice(%{source: :email})

      refute AutoApproval.should_auto_approve?(company, invoice)
    end

    test "returns false with partial extraction even when sender is a company member", %{
      company: company
    } do
      user = insert(:user, email: "member-partial@appunite.com")
      insert(:membership, user: user, company: company, status: :active)
      invoice = build_invoice(%{source: :email, extraction_status: :partial})

      refute AutoApproval.should_auto_approve?(company, invoice,
               sender_email: "member-partial@appunite.com"
             )
    end

    test "returns false with failed extraction even when sender is a company member", %{
      company: company
    } do
      user = insert(:user, email: "member-failed@appunite.com")
      insert(:membership, user: user, company: company, status: :active)
      invoice = build_invoice(%{source: :email, extraction_status: :failed})

      refute AutoApproval.should_auto_approve?(company, invoice,
               sender_email: "member-failed@appunite.com"
             )
    end
  end
end
