defmodule KsefHub.InvoicesTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice

  setup do
    company = insert(:company)
    %{company: company}
  end

  describe "create_invoice/1" do
    test "creates an invoice with valid attributes", %{company: company} do
      attrs =
        params_for(:invoice,
          ksef_number: "1234567890-20250101-ABC123-01",
          company_id: company.id
        )

      assert {:ok, %Invoice{} = invoice} = Invoices.create_invoice(attrs)
      assert invoice.ksef_number == "1234567890-20250101-ABC123-01"
      assert invoice.type == "income"
      assert invoice.status == "pending"
      assert invoice.currency == "PLN"
      assert invoice.company_id == company.id
    end

    test "returns error with invalid type", %{company: company} do
      attrs = params_for(:invoice, type: "invalid", company_id: company.id)
      assert {:error, changeset} = Invoices.create_invoice(attrs)
      assert "is invalid" in errors_on(changeset).type
    end

    test "returns error without required fields" do
      assert {:error, changeset} = Invoices.create_invoice(%{})
      assert errors_on(changeset).type
      assert errors_on(changeset).seller_nip
      assert errors_on(changeset).invoice_number
      assert errors_on(changeset).company_id
    end

    test "enforces unique (company_id, ksef_number)", %{company: company} do
      insert(:invoice, ksef_number: "dup-1", company: company)
      attrs = params_for(:invoice, ksef_number: "dup-1", company_id: company.id)
      assert {:error, changeset} = Invoices.create_invoice(attrs)
      assert errors_on(changeset).company_id
    end
  end

  describe "upsert_invoice/1" do
    test "inserts new invoice and returns :inserted tag", %{company: company} do
      attrs = params_for(:invoice, ksef_number: "upsert-1", company_id: company.id)
      assert {:ok, %Invoice{}, :inserted} = Invoices.upsert_invoice(attrs)
    end

    test "updates existing invoice and returns :updated tag", %{company: company} do
      # Pre-insert with a backdated timestamp so inserted_at != updated_at after upsert
      original =
        insert(:invoice,
          ksef_number: "upsert-2",
          company: company,
          inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
        )

      attrs = params_for(:invoice, ksef_number: "upsert-2", company_id: company.id)

      {:ok, updated, :updated} =
        Invoices.upsert_invoice(%{attrs | seller_name: "Updated Name"})

      assert updated.id == original.id
      assert updated.seller_name == "Updated Name"
    end
  end

  describe "list_invoices/2" do
    test "returns invoices for the company", %{company: company} do
      insert(:invoice, company: company)
      other = insert(:company)
      insert(:invoice, company: other)

      assert [%Invoice{}] = Invoices.list_invoices(company.id)
    end

    test "filters by type", %{company: company} do
      insert(:invoice, type: "income", company: company)
      insert(:invoice, type: "expense", company: company)

      assert [%{type: "income"}] = Invoices.list_invoices(company.id, %{type: "income"})
      assert [%{type: "expense"}] = Invoices.list_invoices(company.id, %{type: "expense"})
    end

    test "filters by status", %{company: company} do
      inv = insert(:invoice, type: "expense", company: company)
      Invoices.approve_invoice(inv)

      assert [%{status: "approved"}] = Invoices.list_invoices(company.id, %{status: "approved"})
      assert [] = Invoices.list_invoices(company.id, %{status: "rejected"})
    end

    test "filters by date range", %{company: company} do
      insert(:invoice, issue_date: ~D[2025-01-01], company: company)
      insert(:invoice, issue_date: ~D[2025-06-15], company: company)

      result =
        Invoices.list_invoices(company.id, %{date_from: ~D[2025-06-01], date_to: ~D[2025-06-30]})

      assert length(result) == 1
    end

    test "filters by seller_nip", %{company: company} do
      insert(:invoice, seller_nip: "1111111111", company: company)
      insert(:invoice, seller_nip: "2222222222", company: company)

      assert [%{seller_nip: "1111111111"}] =
               Invoices.list_invoices(company.id, %{seller_nip: "1111111111"})
    end

    test "searches by query", %{company: company} do
      insert(:invoice, buyer_name: "Acme Corp", company: company)
      insert(:invoice, buyer_name: "Widget Inc", company: company)

      assert [%{buyer_name: "Acme Corp"}] = Invoices.list_invoices(company.id, %{query: "Acme"})
    end

    test "escapes LIKE wildcards in search query", %{company: company} do
      insert(:invoice, buyer_name: "100% Organic", company: company)
      insert(:invoice, buyer_name: "Something Else", company: company)

      assert [%{buyer_name: "100% Organic"}] =
               Invoices.list_invoices(company.id, %{query: "100%"})
    end

    test "escapes underscore wildcards in search query", %{company: company} do
      insert(:invoice, seller_name: "A_B Corp", company: company)
      insert(:invoice, seller_name: "AXB Corp", company: company)

      assert [%{seller_name: "A_B Corp"}] = Invoices.list_invoices(company.id, %{query: "A_B"})
    end

    test "escapes backslash in search query", %{company: company} do
      insert(:invoice, invoice_number: "FV\\2025\\001", company: company)
      insert(:invoice, invoice_number: "FV/2025/002", company: company)

      assert [%{invoice_number: "FV\\2025\\001"}] =
               Invoices.list_invoices(company.id, %{query: "FV\\2025"})
    end

    test "paginates with default page 1 and per_page 25", %{company: company} do
      for i <- 1..30 do
        insert(:invoice, company: company, invoice_number: "FV/#{String.pad_leading("#{i}", 3, "0")}")
      end

      result = Invoices.list_invoices(company.id)
      assert length(result) == 25
    end

    test "respects page and per_page", %{company: company} do
      for i <- 1..10 do
        insert(:invoice, company: company, issue_date: Date.add(~D[2025-01-01], -i))
      end

      page1 = Invoices.list_invoices(company.id, %{per_page: 3, page: 1})
      page2 = Invoices.list_invoices(company.id, %{per_page: 3, page: 2})

      assert length(page1) == 3
      assert length(page2) == 3

      # Pages should not overlap
      page1_ids = MapSet.new(page1, & &1.id)
      page2_ids = MapSet.new(page2, & &1.id)
      assert MapSet.disjoint?(page1_ids, page2_ids)
    end

    test "caps per_page at 100", %{company: company} do
      for i <- 1..105 do
        insert(:invoice, company: company, invoice_number: "FV/#{i}")
      end

      result = Invoices.list_invoices(company.id, %{per_page: 200})
      assert length(result) == 100
    end

    test "excludes xml_content from list results", %{company: company} do
      insert(:invoice, company: company, xml_content: "<xml>big content</xml>")

      [invoice] = Invoices.list_invoices(company.id)
      assert is_nil(invoice.xml_content)
    end
  end

  describe "count_invoices/2" do
    test "returns count scoped to company", %{company: company} do
      insert(:invoice, company: company)
      insert(:invoice, company: company)
      other = insert(:company)
      insert(:invoice, company: other)

      assert Invoices.count_invoices(company.id) == 2
    end

    test "applies filters to count", %{company: company} do
      insert(:invoice, company: company, type: "income")
      insert(:invoice, company: company, type: "expense")

      assert Invoices.count_invoices(company.id, %{type: "income"}) == 1
    end
  end

  describe "list_invoices_paginated/2" do
    test "returns paginated result with metadata", %{company: company} do
      for i <- 1..10 do
        insert(:invoice, company: company, invoice_number: "FV/#{i}")
      end

      result = Invoices.list_invoices_paginated(company.id, %{per_page: 3, page: 2})

      assert length(result.entries) == 3
      assert result.page == 2
      assert result.per_page == 3
      assert result.total_count == 10
      assert result.total_pages == 4
    end

    test "returns total_pages of 1 when no results", %{company: company} do
      result = Invoices.list_invoices_paginated(company.id)

      assert result.entries == []
      assert result.total_count == 0
      assert result.total_pages == 1
    end
  end

  describe "get_invoice!/2" do
    test "returns invoice scoped to company", %{company: company} do
      inv = insert(:invoice, company: company)
      assert %Invoice{} = Invoices.get_invoice!(company.id, inv.id)
    end

    test "raises when invoice belongs to different company", %{company: company} do
      other = insert(:company)
      inv = insert(:invoice, company: other)

      assert_raise Ecto.NoResultsError, fn ->
        Invoices.get_invoice!(company.id, inv.id)
      end
    end
  end

  describe "approve_invoice/1" do
    test "approves an expense invoice", %{company: company} do
      inv = insert(:invoice, type: "expense", company: company)
      assert {:ok, %Invoice{status: "approved"}} = Invoices.approve_invoice(inv)
    end

    test "rejects approving an income invoice", %{company: company} do
      inv = insert(:invoice, type: "income", company: company)
      assert {:error, {:invalid_type, "income"}} = Invoices.approve_invoice(inv)
    end
  end

  describe "reject_invoice/1" do
    test "rejects an expense invoice", %{company: company} do
      inv = insert(:invoice, type: "expense", company: company)
      assert {:ok, %Invoice{status: "rejected"}} = Invoices.reject_invoice(inv)
    end

    test "rejects rejecting an income invoice", %{company: company} do
      inv = insert(:invoice, type: "income", company: company)
      assert {:error, {:invalid_type, "income"}} = Invoices.reject_invoice(inv)
    end
  end

  describe "count_by_type_and_status/1" do
    test "returns counts scoped to company", %{company: company} do
      insert(:invoice, type: "income", company: company)
      insert(:invoice, type: "expense", company: company)

      # Invoice in another company should not be counted
      other = insert(:company)
      insert(:invoice, type: "income", company: other)

      counts = Invoices.count_by_type_and_status(company.id)
      assert counts[{"income", "pending"}] == 1
      assert counts[{"expense", "pending"}] == 1
    end
  end
end
