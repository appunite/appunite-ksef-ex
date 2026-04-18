defmodule KsefHub.Invoices.AccessControlTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice

  @sample_xml File.read!("test/support/fixtures/sample_income.xml")

  setup do
    company = insert(:company)
    %{company: company}
  end

  describe "role-based scoping via access control" do
    setup %{company: company} do
      reviewer = insert(:user)
      insert(:membership, user: reviewer, company: company, role: :reviewer)
      %{reviewer: reviewer}
    end

    test "income invoices are auto-restricted on creation", %{company: company} do
      attrs =
        params_for(:invoice, company_id: company.id, type: :income)
        |> Map.put(:xml_content, @sample_xml)

      assert {:ok, invoice} = Invoices.create_invoice(attrs)
      assert invoice.access_restricted == true
    end

    test "expense invoices are not auto-restricted", %{company: company} do
      attrs =
        params_for(:manual_invoice, company_id: company.id, type: :expense)

      assert {:ok, invoice} = Invoices.create_manual_invoice(company.id, attrs)
      assert invoice.access_restricted == false
    end

    test "reviewer cannot see income invoices without grant", %{
      company: company,
      reviewer: reviewer
    } do
      insert(:invoice, type: :income, company: company, access_restricted: true)
      insert(:invoice, type: :expense, company: company)

      result =
        Invoices.list_invoices_paginated(company.id, %{},
          role: :reviewer,
          user_id: reviewer.id
        )

      assert result.total_count == 1
      assert hd(result.entries).type == :expense
    end

    test "reviewer can see income invoice when granted access", %{
      company: company,
      reviewer: reviewer
    } do
      income = insert(:invoice, type: :income, company: company, access_restricted: true)
      Invoices.grant_access(income.id, reviewer.id)

      result =
        Invoices.list_invoices_paginated(company.id, %{type: :income},
          role: :reviewer,
          user_id: reviewer.id
        )

      assert result.total_count == 1
      assert hd(result.entries).type == :income
    end

    test "get_invoice with role: reviewer returns nil for income invoice without grant", %{
      company: company,
      reviewer: reviewer
    } do
      income = insert(:invoice, type: :income, company: company, access_restricted: true)

      assert is_nil(
               Invoices.get_invoice(company.id, income.id,
                 role: :reviewer,
                 user_id: reviewer.id
               )
             )
    end

    test "get_invoice with role: reviewer returns expense invoice", %{
      company: company,
      reviewer: reviewer
    } do
      expense = insert(:invoice, type: :expense, company: company)

      assert %Invoice{} =
               Invoices.get_invoice(company.id, expense.id,
                 role: :reviewer,
                 user_id: reviewer.id
               )
    end

    test "get_invoice! with role: reviewer raises for income invoice without grant", %{
      company: company,
      reviewer: reviewer
    } do
      income = insert(:invoice, type: :income, company: company, access_restricted: true)

      assert_raise Ecto.NoResultsError, fn ->
        Invoices.get_invoice!(company.id, income.id, role: :reviewer, user_id: reviewer.id)
      end
    end

    test "owner sees all invoices including restricted income", %{company: company} do
      owner = insert(:user)
      insert(:membership, user: owner, company: company, role: :owner)

      insert(:invoice, type: :income, company: company)
      insert(:invoice, type: :expense, company: company)

      result =
        Invoices.list_invoices_paginated(company.id, %{}, role: :owner, user_id: owner.id)

      assert result.total_count == 2
    end

    test "role: nil without user_id denies restricted invoices", %{company: company} do
      insert(:invoice, type: :income, company: company, access_restricted: true)
      insert(:invoice, type: :expense, company: company, access_restricted: false)

      result = Invoices.list_invoices_paginated(company.id, %{}, role: nil)
      assert result.total_count == 1
    end

    test "internal system calls (no role, no user_id) see all invoices", %{company: company} do
      insert(:invoice, type: :income, company: company, access_restricted: true)
      insert(:invoice, type: :expense, company: company)

      result = Invoices.list_invoices_paginated(company.id, %{}, [])
      assert result.total_count == 2
    end

    test "count_invoices for reviewer excludes restricted income", %{
      company: company,
      reviewer: reviewer
    } do
      insert(:invoice, type: :income, company: company, access_restricted: true)
      insert(:invoice, type: :expense, company: company)
      insert(:invoice, type: :expense, company: company)

      assert Invoices.count_invoices(company.id, %{},
               role: :reviewer,
               user_id: reviewer.id
             ) == 2
    end
  end

  describe "access control" do
    setup %{company: company} do
      reviewer = insert(:user)
      insert(:membership, user: reviewer, company: company, role: :reviewer)

      other_reviewer = insert(:user)
      insert(:membership, user: other_reviewer, company: company, role: :reviewer)

      admin = insert(:user)
      insert(:membership, user: admin, company: company, role: :admin)

      owner = insert(:user)
      insert(:membership, user: owner, company: company, role: :owner)

      accountant = insert(:user)
      insert(:membership, user: accountant, company: company, role: :accountant)

      %{
        reviewer: reviewer,
        other_reviewer: other_reviewer,
        admin: admin,
        owner: owner,
        accountant: accountant
      }
    end

    test "grant_access creates a grant record", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense)
      user = insert(:user)
      insert(:membership, user: user, company: company, role: :reviewer)
      granter = insert(:user)

      assert {:ok, grant} = Invoices.grant_access(invoice.id, user.id, granter.id)
      assert grant.invoice_id == invoice.id
    end

    test "grant_access is idempotent", %{company: company, reviewer: reviewer} do
      invoice = insert(:invoice, company: company, type: :expense)

      assert {:ok, _} = Invoices.grant_access(invoice.id, reviewer.id)
      assert {:ok, _} = Invoices.grant_access(invoice.id, reviewer.id)

      grants = Invoices.list_access_grants(invoice.id)
      assert length(grants) == 1
    end

    test "grant_access rejects non-member user", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense)
      outsider = insert(:user)

      assert {:error, changeset} = Invoices.grant_access(invoice.id, outsider.id)
      assert changeset.errors[:user_id]
    end

    test "grant_access rejects user with full visibility role", %{company: company, admin: admin} do
      invoice = insert(:invoice, company: company, type: :expense)

      assert {:error, changeset} = Invoices.grant_access(invoice.id, admin.id)
      assert {msg, _} = changeset.errors[:user_id]
      assert msg =~ "full access"
    end

    test "revoke_access removes a grant", %{company: company, reviewer: reviewer} do
      invoice = insert(:invoice, company: company, type: :expense)

      {:ok, _} = Invoices.grant_access(invoice.id, reviewer.id)
      assert {:ok, _} = Invoices.revoke_access(invoice.id, reviewer.id)

      assert Invoices.list_access_grants(invoice.id) == []
    end

    test "revoke_access returns error when no grant exists", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense)
      user = insert(:user)

      assert {:error, :not_found} = Invoices.revoke_access(invoice.id, user.id)
    end

    test "list_access_grants returns grants with preloaded user", %{
      company: company,
      reviewer: reviewer
    } do
      invoice = insert(:invoice, company: company, type: :expense)

      {:ok, _} = Invoices.grant_access(invoice.id, reviewer.id)
      grants = Invoices.list_access_grants(invoice.id)

      assert [grant] = grants
      assert grant.user.id == reviewer.id
    end

    test "set_access_restricted toggles the flag", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense)

      assert {:ok, updated} = Invoices.set_access_restricted(invoice, true)
      assert updated.access_restricted == true

      assert {:ok, updated} = Invoices.set_access_restricted(updated, false)
      assert updated.access_restricted == false
    end

    test "reviewer sees all invoices when access_restricted is false", %{
      company: company,
      reviewer: reviewer
    } do
      insert(:invoice, company: company, type: :expense, access_restricted: false)
      insert(:invoice, company: company, type: :expense, access_restricted: false)

      result =
        Invoices.list_invoices(company.id, %{}, role: :reviewer, user_id: reviewer.id)

      assert length(result) == 2
    end

    test "reviewer with grant sees restricted invoice", %{
      company: company,
      reviewer: reviewer
    } do
      invoice =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      Invoices.grant_access(invoice.id, reviewer.id)

      result =
        Invoices.list_invoices(company.id, %{}, role: :reviewer, user_id: reviewer.id)

      assert length(result) == 1
    end

    test "reviewer without grant does NOT see restricted invoice", %{
      company: company,
      reviewer: reviewer
    } do
      insert(:invoice, company: company, type: :expense, access_restricted: true)

      result =
        Invoices.list_invoices(company.id, %{}, role: :reviewer, user_id: reviewer.id)

      assert result == []
    end

    test "reviewer sees mix of public and restricted-but-granted invoices", %{
      company: company,
      reviewer: reviewer
    } do
      public = insert(:invoice, company: company, type: :expense, access_restricted: false)

      restricted_granted =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      _restricted_no_grant =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      Invoices.grant_access(restricted_granted.id, reviewer.id)

      result =
        Invoices.list_invoices(company.id, %{}, role: :reviewer, user_id: reviewer.id)

      ids = Enum.map(result, & &1.id) |> MapSet.new()
      assert MapSet.member?(ids, public.id)
      assert MapSet.member?(ids, restricted_granted.id)
      assert length(result) == 2
    end

    test "restricted invoice with no grants is invisible to all reviewers", %{
      company: company,
      reviewer: reviewer,
      other_reviewer: other_reviewer
    } do
      insert(:invoice, company: company, type: :expense, access_restricted: true)

      assert Invoices.list_invoices(company.id, %{},
               role: :reviewer,
               user_id: reviewer.id
             ) == []

      assert Invoices.list_invoices(company.id, %{},
               role: :reviewer,
               user_id: other_reviewer.id
             ) == []
    end

    test "owner sees all invoices regardless of access_restricted", %{
      company: company,
      owner: owner
    } do
      insert(:invoice, company: company, type: :expense, access_restricted: true)
      insert(:invoice, company: company, type: :expense, access_restricted: false)
      insert(:invoice, company: company, type: :income, access_restricted: true)

      result = Invoices.list_invoices(company.id, %{}, role: :owner, user_id: owner.id)
      assert length(result) == 3
    end

    test "admin sees all invoices regardless of access_restricted", %{
      company: company,
      admin: admin
    } do
      insert(:invoice, company: company, type: :expense, access_restricted: true)
      insert(:invoice, company: company, type: :income, access_restricted: true)

      result = Invoices.list_invoices(company.id, %{}, role: :admin, user_id: admin.id)
      assert length(result) == 2
    end

    test "accountant sees all invoices regardless of access_restricted", %{
      company: company,
      accountant: accountant
    } do
      insert(:invoice, company: company, type: :expense, access_restricted: true)
      insert(:invoice, company: company, type: :income, access_restricted: true)

      result =
        Invoices.list_invoices(company.id, %{}, role: :accountant, user_id: accountant.id)

      assert length(result) == 2
    end

    test "get_invoice returns nil for restricted invoice when reviewer lacks grant", %{
      company: company,
      reviewer: reviewer
    } do
      invoice =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      assert Invoices.get_invoice(company.id, invoice.id,
               role: :reviewer,
               user_id: reviewer.id
             ) == nil
    end

    test "get_invoice returns invoice for restricted invoice when reviewer has grant", %{
      company: company,
      reviewer: reviewer
    } do
      invoice =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      Invoices.grant_access(invoice.id, reviewer.id)

      assert %Invoice{} =
               Invoices.get_invoice(company.id, invoice.id,
                 role: :reviewer,
                 user_id: reviewer.id
               )
    end

    test "count_invoices matches filtered list for reviewer", %{
      company: company,
      reviewer: reviewer
    } do
      insert(:invoice, company: company, type: :expense, access_restricted: false)

      restricted =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      Invoices.grant_access(restricted.id, reviewer.id)

      opts = [role: :reviewer, user_id: reviewer.id]

      list = Invoices.list_invoices(company.id, %{}, opts)
      count = Invoices.count_invoices(company.id, %{}, opts)

      assert length(list) == count
      assert count == 2
    end

    test "list_invoices_paginated total_count and entries respect access filtering", %{
      company: company,
      reviewer: reviewer
    } do
      insert(:invoice, company: company, type: :expense, access_restricted: false)
      insert(:invoice, company: company, type: :expense, access_restricted: true)

      restricted_granted =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      Invoices.grant_access(restricted_granted.id, reviewer.id)

      result =
        Invoices.list_invoices_paginated(company.id, %{},
          role: :reviewer,
          user_id: reviewer.id
        )

      assert result.total_count == 2
      assert length(result.entries) == 2

      ids = MapSet.new(result.entries, & &1.id)
      assert MapSet.member?(ids, restricted_granted.id)
    end

    test "get_invoice_with_details returns nil for restricted invoice when reviewer lacks grant",
         %{company: company, reviewer: reviewer} do
      invoice =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      assert Invoices.get_invoice_with_details(company.id, invoice.id,
               role: :reviewer,
               user_id: reviewer.id
             ) == nil
    end

    test "get_invoice_with_details returns invoice when reviewer has grant", %{
      company: company,
      reviewer: reviewer
    } do
      invoice =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      Invoices.grant_access(invoice.id, reviewer.id)

      assert %Invoice{} =
               Invoices.get_invoice_with_details(company.id, invoice.id,
                 role: :reviewer,
                 user_id: reviewer.id
               )
    end

    test "income invoices are auto-restricted so reviewer cannot see them by default", %{
      company: company,
      reviewer: reviewer
    } do
      # Income invoices get access_restricted: true automatically
      attrs =
        params_for(:invoice, company_id: company.id, type: :income)
        |> Map.put(:xml_content, File.read!("test/support/fixtures/sample_income.xml"))

      {:ok, income} = Invoices.create_invoice(attrs)
      assert income.access_restricted == true

      insert(:invoice, company: company, type: :expense, access_restricted: false)

      result =
        Invoices.list_invoices(company.id, %{}, role: :reviewer, user_id: reviewer.id)

      assert length(result) == 1
      assert hd(result).type == :expense
    end

    test "expense invoices with purchase_order are auto-restricted", %{
      company: company,
      reviewer: reviewer
    } do
      attrs =
        params_for(:invoice,
          company_id: company.id,
          type: :expense,
          purchase_order: "PO-2026-001"
        )
        |> Map.put(:xml_content, File.read!("test/support/fixtures/sample_expense.xml"))

      {:ok, invoice} = Invoices.create_invoice(attrs)
      assert invoice.access_restricted == true

      insert(:invoice, company: company, type: :expense, access_restricted: false)

      result =
        Invoices.list_invoices(company.id, %{}, role: :reviewer, user_id: reviewer.id)

      assert length(result) == 1
      refute hd(result).id == invoice.id
    end

    test "upserted expense invoice with purchase_order is auto-restricted", %{
      company: company,
      reviewer: reviewer
    } do
      attrs =
        params_for(:invoice,
          company_id: company.id,
          type: :expense,
          ksef_number: "upsert-po-restrict",
          purchase_order: "PO-2026-002"
        )
        |> Map.put(:xml_content, File.read!("test/support/fixtures/sample_expense.xml"))

      assert {:ok, invoice, :inserted} = Invoices.upsert_invoice(attrs)
      assert invoice.access_restricted == true

      result =
        Invoices.list_invoices(company.id, %{}, role: :reviewer, user_id: reviewer.id)

      refute Enum.any?(result, &(&1.id == invoice.id))
    end

    test "expense invoices without purchase_order are not auto-restricted", %{company: company} do
      attrs =
        params_for(:invoice, company_id: company.id, type: :expense, purchase_order: nil)
        |> Map.put(:xml_content, File.read!("test/support/fixtures/sample_expense.xml"))

      {:ok, invoice} = Invoices.create_invoice(attrs)
      assert invoice.access_restricted == false
    end

    test "expense invoice with purchase_order can be unrestricted by admin", %{company: company} do
      invoice =
        insert(:invoice,
          company: company,
          type: :expense,
          purchase_order: "PO-123",
          access_restricted: true
        )

      assert {:ok, unrestricted} = Invoices.set_access_restricted(invoice, false)
      assert unrestricted.access_restricted == false
    end

    test "income invoice cannot be unrestricted", %{company: company} do
      invoice =
        insert(:invoice, company: company, type: :income, access_restricted: true)

      assert {:error, :income_always_restricted} =
               Invoices.set_access_restricted(invoice, false)

      # Verify it's still restricted
      reloaded = KsefHub.Repo.reload!(invoice)
      assert reloaded.access_restricted == true
    end

    test "expense invoice can be toggled freely", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense)

      assert {:ok, restricted} = Invoices.set_access_restricted(invoice, true)
      assert restricted.access_restricted == true

      assert {:ok, unrestricted} = Invoices.set_access_restricted(restricted, false)
      assert unrestricted.access_restricted == false
    end

    test "grant_access to non-member returns error", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense, access_restricted: true)
      non_member = insert(:user)

      assert {:error, changeset} = Invoices.grant_access(invoice.id, non_member.id)
      assert changeset.errors[:user_id]
    end

    test "grant_access to admin returns error (already has full access)", %{
      company: company,
      admin: admin
    } do
      invoice =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      assert {:error, changeset} = Invoices.grant_access(invoice.id, admin.id)
      assert changeset.errors[:user_id]
    end

    test "upsert_invoice auto-restricts income invoices", %{company: company} do
      attrs = %{
        company_id: company.id,
        type: :income,
        source: :ksef,
        ksef_number: "auto-restrict-test-001",
        seller_nip: "1234567890",
        seller_name: "Seller",
        buyer_nip: "0987654321",
        buyer_name: "Buyer",
        invoice_number: "FV/AR/001",
        issue_date: ~D[2026-03-01],
        net_amount: Decimal.new("100.00"),
        gross_amount: Decimal.new("123.00"),
        xml_content: File.read!("test/support/fixtures/sample_income.xml")
      }

      assert {:ok, invoice, :inserted} = Invoices.upsert_invoice(attrs)
      assert invoice.access_restricted == true
    end

    test "grants are cleaned up when invoice is deleted", %{company: company, reviewer: reviewer} do
      invoice = insert(:invoice, company: company, type: :expense)

      {:ok, _} = Invoices.grant_access(invoice.id, reviewer.id)
      assert length(Invoices.list_access_grants(invoice.id)) == 1

      KsefHub.Repo.delete!(invoice)
      assert Invoices.list_access_grants(invoice.id) == []
    end
  end

  describe "viewer role access" do
    setup %{company: company} do
      viewer = insert(:user)
      insert(:membership, user: viewer, company: company, role: :viewer)
      %{viewer: viewer}
    end

    test "viewer cannot see income invoices without explicit grant (same filtering as reviewer)",
         %{company: company, viewer: viewer} do
      insert(:invoice, type: :income, company: company, access_restricted: true)
      insert(:invoice, type: :expense, company: company, access_restricted: false)

      result =
        Invoices.list_invoices_paginated(company.id, %{}, role: :viewer, user_id: viewer.id)

      assert result.total_count == 1
      assert hd(result.entries).type == :expense
    end

    test "viewer cannot see restricted expense invoices without grant", %{
      company: company,
      viewer: viewer
    } do
      insert(:invoice, type: :expense, company: company, access_restricted: true)

      result =
        Invoices.list_invoices_paginated(company.id, %{}, role: :viewer, user_id: viewer.id)

      assert result.total_count == 0
    end

    test "viewer sees income invoice when granted access", %{company: company, viewer: viewer} do
      income = insert(:invoice, type: :income, company: company, access_restricted: true)
      Invoices.grant_access(income.id, viewer.id)

      result =
        Invoices.list_invoices_paginated(company.id, %{}, role: :viewer, user_id: viewer.id)

      assert result.total_count == 1
      assert hd(result.entries).type == :income
    end

    test "get_invoice returns nil for restricted invoice without grant", %{
      company: company,
      viewer: viewer
    } do
      restricted = insert(:invoice, company: company, type: :expense, access_restricted: true)

      assert is_nil(
               Invoices.get_invoice(company.id, restricted.id, role: :viewer, user_id: viewer.id)
             )
    end

    test "get_invoice returns nil when scoped to viewer's company but invoice belongs elsewhere",
         %{company: company, viewer: viewer} do
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company)

      assert is_nil(
               Invoices.get_invoice(company.id, invoice.id, role: :viewer, user_id: viewer.id)
             )
    end

    test "viewer can be a grant recipient (does not have full visibility)", %{
      company: company,
      viewer: viewer
    } do
      invoice = insert(:invoice, company: company, type: :income, access_restricted: true)

      assert {:ok, _grant} = Invoices.grant_access(invoice.id, viewer.id)
    end
  end

  describe "IDOR: company scoping prevents cross-company access" do
    test "get_invoice scopes by company_id — cannot access invoice from different company" do
      company_a = insert(:company)
      company_b = insert(:company)
      user = insert(:user)
      insert(:membership, user: user, company: company_a, role: :owner)

      invoice_b = insert(:invoice, company: company_b)

      # Attempt to fetch company_b's invoice using company_a's scope
      assert is_nil(Invoices.get_invoice(company_a.id, invoice_b.id, role: :owner, user_id: user.id))
    end

    test "get_invoice! raises when company_id does not match invoice" do
      company_a = insert(:company)
      company_b = insert(:company)
      user = insert(:user)
      insert(:membership, user: user, company: company_a, role: :owner)

      invoice_b = insert(:invoice, company: company_b)

      assert_raise Ecto.NoResultsError, fn ->
        Invoices.get_invoice!(company_a.id, invoice_b.id, role: :owner, user_id: user.id)
      end
    end

    test "get_invoice_with_details returns nil for invoice from different company" do
      company_a = insert(:company)
      company_b = insert(:company)
      user = insert(:user)
      insert(:membership, user: user, company: company_a, role: :admin)

      invoice_b = insert(:invoice, company: company_b)

      assert is_nil(
               Invoices.get_invoice_with_details(company_a.id, invoice_b.id,
                 role: :admin,
                 user_id: user.id
               )
             )
    end

    test "list_invoices never returns invoices from another company" do
      company_a = insert(:company)
      company_b = insert(:company)
      user = insert(:user)
      insert(:membership, user: user, company: company_a, role: :owner)

      insert(:invoice, company: company_a)
      insert(:invoice, company: company_b)
      insert(:invoice, company: company_b)

      results = Invoices.list_invoices(company_a.id, %{}, role: :owner, user_id: user.id)
      assert length(results) == 1
      assert hd(results).company_id == company_a.id
    end

    test "viewer cannot access invoice from their company using another company's ID" do
      company_a = insert(:company)
      company_b = insert(:company)
      viewer = insert(:user)
      insert(:membership, user: viewer, company: company_a, role: :viewer)

      invoice_a = insert(:invoice, company: company_a)

      # Try to access company_a's invoice scoped under company_b
      assert is_nil(
               Invoices.get_invoice(company_b.id, invoice_a.id,
                 role: :viewer,
                 user_id: viewer.id
               )
             )
    end
  end
end
