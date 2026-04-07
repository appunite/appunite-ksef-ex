defmodule KsefHub.ActivityLogTest do
  use KsefHub.DataCase, async: true

  alias KsefHub.ActivityLog

  import KsefHub.Factory

  setup do
    company = insert(:company)
    user = insert(:user)
    %{company: company, user: user}
  end

  describe "list_for_invoice/3" do
    test "returns entries scoped to a specific invoice", %{company: company, user: user} do
      invoice_id = Ecto.UUID.generate()
      other_invoice_id = Ecto.UUID.generate()

      insert(:audit_log,
        company: company,
        user: user,
        resource_type: "invoice",
        resource_id: invoice_id,
        action: "invoice.created"
      )

      insert(:audit_log,
        company: company,
        user: user,
        resource_type: "invoice",
        resource_id: other_invoice_id,
        action: "invoice.created"
      )

      entries = ActivityLog.list_for_invoice(company.id, invoice_id)
      assert length(entries) == 1
      assert hd(entries).resource_id == invoice_id
    end

    test "returns entries ordered by inserted_at desc", %{company: company, user: user} do
      invoice_id = Ecto.UUID.generate()

      entries = ActivityLog.list_for_invoice(company.id, invoice_id)
      assert entries == []

      insert(:audit_log,
        company: company,
        user: user,
        resource_type: "invoice",
        resource_id: invoice_id,
        action: "invoice.created"
      )

      insert(:audit_log,
        company: company,
        user: user,
        resource_type: "invoice",
        resource_id: invoice_id,
        action: "invoice.status_changed"
      )

      entries = ActivityLog.list_for_invoice(company.id, invoice_id)
      assert length(entries) == 2

      # Verify ordering: each entry's inserted_at >= next entry's inserted_at
      [first, second] = entries
      assert NaiveDateTime.compare(first.inserted_at, second.inserted_at) in [:gt, :eq]
    end

    test "orders by sequence when inserted_at is identical", %{company: company, user: user} do
      invoice_id = Ecto.UUID.generate()
      now = NaiveDateTime.utc_now()

      first =
        insert(:audit_log,
          company: company,
          user: user,
          resource_type: "invoice",
          resource_id: invoice_id,
          action: "invoice.created",
          inserted_at: now
        )

      second =
        insert(:audit_log,
          company: company,
          user: user,
          resource_type: "invoice",
          resource_id: invoice_id,
          action: "invoice.status_changed",
          inserted_at: now
        )

      third =
        insert(:audit_log,
          company: company,
          user: user,
          resource_type: "invoice",
          resource_id: invoice_id,
          action: "invoice.category_updated",
          inserted_at: now
        )

      entries = ActivityLog.list_for_invoice(company.id, invoice_id)
      assert Enum.map(entries, & &1.id) == [third.id, second.id, first.id]
    end

    test "respects limit option", %{company: company, user: user} do
      invoice_id = Ecto.UUID.generate()

      for action <- ~w(invoice.created invoice.updated invoice.status_changed) do
        insert(:audit_log,
          company: company,
          user: user,
          resource_type: "invoice",
          resource_id: invoice_id,
          action: action
        )
      end

      entries = ActivityLog.list_for_invoice(company.id, invoice_id, limit: 2)
      assert length(entries) == 2
    end

    test "does not return entries from other companies", %{user: user} do
      company_a = insert(:company)
      company_b = insert(:company)
      invoice_id = Ecto.UUID.generate()

      insert(:audit_log,
        company: company_a,
        user: user,
        resource_type: "invoice",
        resource_id: invoice_id,
        action: "invoice.created"
      )

      assert ActivityLog.list_for_invoice(company_b.id, invoice_id) == []
    end
  end

  describe "list_for_company/2" do
    test "returns paginated entries for a company", %{company: company, user: user} do
      for i <- 1..5 do
        insert(:audit_log,
          company: company,
          user: user,
          action: "invoice.created",
          resource_id: Ecto.UUID.generate(),
          metadata: %{index: i}
        )
      end

      result = ActivityLog.list_for_company(company.id, per_page: 2, page: 1)
      assert length(result.entries) == 2
      assert result.total_count == 5
      assert result.total_pages == 3
      assert result.page == 1
      assert result.per_page == 2
    end

    test "filters by action_prefix", %{company: company, user: user} do
      insert(:audit_log, company: company, user: user, action: "invoice.created")
      insert(:audit_log, company: company, user: user, action: "team.member_invited")

      result = ActivityLog.list_for_company(company.id, action_prefix: "invoice")
      assert length(result.entries) == 1
      assert hd(result.entries).action == "invoice.created"
    end

    test "filters by resource_type", %{company: company, user: user} do
      insert(:audit_log,
        company: company,
        user: user,
        action: "invoice.created",
        resource_type: "invoice"
      )

      insert(:audit_log,
        company: company,
        user: user,
        action: "bank_account.created",
        resource_type: "bank_account"
      )

      result = ActivityLog.list_for_company(company.id, resource_type: "bank_account")
      assert length(result.entries) == 1
      assert hd(result.entries).resource_type == "bank_account"
    end
  end

  describe "list_invoice_timeline/3" do
    test "includes payment request events linked via metadata", %{company: company, user: user} do
      invoice_id = Ecto.UUID.generate()

      insert(:audit_log,
        company: company,
        user: user,
        resource_type: "invoice",
        resource_id: invoice_id,
        action: "invoice.created"
      )

      insert(:audit_log,
        company: company,
        user: user,
        resource_type: "payment_request",
        resource_id: Ecto.UUID.generate(),
        action: "payment_request.created",
        metadata: %{invoice_id: invoice_id}
      )

      entries = ActivityLog.list_invoice_timeline(company.id, invoice_id)
      assert length(entries) == 2
      actions = Enum.map(entries, & &1.action)
      assert "invoice.created" in actions
      assert "payment_request.created" in actions
    end
  end
end
