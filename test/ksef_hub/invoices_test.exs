defmodule KsefHub.InvoicesTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice

  describe "create_invoice/1" do
    test "creates an invoice with valid attributes" do
      attrs = params_for(:invoice, ksef_number: "1234567890-20250101-ABC123-01")
      assert {:ok, %Invoice{} = invoice} = Invoices.create_invoice(attrs)
      assert invoice.ksef_number == "1234567890-20250101-ABC123-01"
      assert invoice.type == "income"
      assert invoice.status == "pending"
      assert invoice.currency == "PLN"
    end

    test "returns error with invalid type" do
      attrs = params_for(:invoice, type: "invalid")
      assert {:error, changeset} = Invoices.create_invoice(attrs)
      assert "is invalid" in errors_on(changeset).type
    end

    test "returns error without required fields" do
      assert {:error, changeset} = Invoices.create_invoice(%{})
      assert errors_on(changeset).type
      assert errors_on(changeset).seller_nip
      assert errors_on(changeset).invoice_number
    end

    test "enforces unique ksef_number" do
      insert(:invoice, ksef_number: "dup-1")
      attrs = params_for(:invoice, ksef_number: "dup-1")
      assert {:error, changeset} = Invoices.create_invoice(attrs)
      assert "has already been taken" in errors_on(changeset).ksef_number
    end
  end

  describe "upsert_invoice/1" do
    test "inserts new invoice" do
      attrs = params_for(:invoice, ksef_number: "upsert-1")
      assert {:ok, %Invoice{}} = Invoices.upsert_invoice(attrs)
    end

    test "updates existing invoice on ksef_number conflict" do
      attrs = params_for(:invoice, ksef_number: "upsert-2")
      {:ok, original} = Invoices.upsert_invoice(attrs)

      {:ok, updated} =
        Invoices.upsert_invoice(%{attrs | seller_name: "Updated Name"})

      assert updated.id == original.id
      assert updated.seller_name == "Updated Name"
    end
  end

  describe "list_invoices/1" do
    test "returns all invoices" do
      insert(:invoice)
      assert [%Invoice{}] = Invoices.list_invoices()
    end

    test "filters by type" do
      insert(:invoice, type: "income")
      insert(:invoice, type: "expense")

      assert [%{type: "income"}] = Invoices.list_invoices(%{type: "income"})
      assert [%{type: "expense"}] = Invoices.list_invoices(%{type: "expense"})
    end

    test "filters by status" do
      inv = insert(:invoice, type: "expense")
      Invoices.approve_invoice(inv)

      assert [%{status: "approved"}] = Invoices.list_invoices(%{status: "approved"})
      assert [] = Invoices.list_invoices(%{status: "rejected"})
    end

    test "filters by date range" do
      insert(:invoice, issue_date: ~D[2025-01-01])
      insert(:invoice, issue_date: ~D[2025-06-15])

      result = Invoices.list_invoices(%{date_from: ~D[2025-06-01], date_to: ~D[2025-06-30]})
      assert length(result) == 1
    end

    test "filters by seller_nip" do
      insert(:invoice, seller_nip: "1111111111")
      insert(:invoice, seller_nip: "2222222222")

      assert [%{seller_nip: "1111111111"}] = Invoices.list_invoices(%{seller_nip: "1111111111"})
    end

    test "searches by query" do
      insert(:invoice, buyer_name: "Acme Corp")
      insert(:invoice, buyer_name: "Widget Inc")

      assert [%{buyer_name: "Acme Corp"}] = Invoices.list_invoices(%{query: "Acme"})
    end

    test "escapes LIKE wildcards in search query" do
      insert(:invoice, buyer_name: "100% Organic")
      insert(:invoice, buyer_name: "Something Else")

      assert [%{buyer_name: "100% Organic"}] = Invoices.list_invoices(%{query: "100%"})
    end

    test "escapes underscore wildcards in search query" do
      insert(:invoice, seller_name: "A_B Corp")
      insert(:invoice, seller_name: "AXB Corp")

      assert [%{seller_name: "A_B Corp"}] = Invoices.list_invoices(%{query: "A_B"})
    end

    test "escapes backslash in search query" do
      insert(:invoice, invoice_number: "FV\\2025\\001")
      insert(:invoice, invoice_number: "FV/2025/002")

      assert [%{invoice_number: "FV\\2025\\001"}] = Invoices.list_invoices(%{query: "FV\\2025"})
    end
  end

  describe "approve_invoice/1" do
    test "approves an expense invoice" do
      inv = insert(:invoice, type: "expense")
      assert {:ok, %Invoice{status: "approved"}} = Invoices.approve_invoice(inv)
    end

    test "rejects approving an income invoice" do
      inv = insert(:invoice, type: "income")
      assert {:error, {:invalid_type, "income"}} = Invoices.approve_invoice(inv)
    end
  end

  describe "reject_invoice/1" do
    test "rejects an expense invoice" do
      inv = insert(:invoice, type: "expense")
      assert {:ok, %Invoice{status: "rejected"}} = Invoices.reject_invoice(inv)
    end

    test "rejects rejecting an income invoice" do
      inv = insert(:invoice, type: "income")
      assert {:error, {:invalid_type, "income"}} = Invoices.reject_invoice(inv)
    end
  end

  describe "count_by_type_and_status/0" do
    test "returns counts grouped by type and status" do
      insert(:invoice, type: "income")
      insert(:invoice, type: "expense")

      counts = Invoices.count_by_type_and_status()
      assert counts[{"income", "pending"}] == 1
      assert counts[{"expense", "pending"}] == 1
    end
  end
end
