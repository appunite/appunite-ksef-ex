defmodule KsefHub.InvoicesTest do
  use KsefHub.DataCase, async: true

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice

  @valid_attrs %{
    ksef_number: "1234567890-20250101-ABC123-01",
    type: "income",
    seller_nip: "1234567890",
    seller_name: "Seller Sp. z o.o.",
    buyer_nip: "0987654321",
    buyer_name: "Buyer S.A.",
    invoice_number: "FV/2025/001",
    issue_date: ~D[2025-01-15],
    net_amount: Decimal.new("1000.00"),
    vat_amount: Decimal.new("230.00"),
    gross_amount: Decimal.new("1230.00"),
    currency: "PLN",
    xml_content: "<Faktura>...</Faktura>"
  }

  defp create_invoice(attrs \\ %{}) do
    {:ok, invoice} = Invoices.create_invoice(Map.merge(@valid_attrs, attrs))
    invoice
  end

  describe "create_invoice/1" do
    test "creates an invoice with valid attributes" do
      assert {:ok, %Invoice{} = invoice} = Invoices.create_invoice(@valid_attrs)
      assert invoice.ksef_number == "1234567890-20250101-ABC123-01"
      assert invoice.type == "income"
      assert invoice.status == "pending"
      assert invoice.currency == "PLN"
    end

    test "returns error with invalid type" do
      assert {:error, changeset} = Invoices.create_invoice(%{@valid_attrs | type: "invalid"})
      assert "is invalid" in errors_on(changeset).type
    end

    test "returns error without required fields" do
      assert {:error, changeset} = Invoices.create_invoice(%{})
      assert errors_on(changeset).type
      assert errors_on(changeset).seller_nip
      assert errors_on(changeset).invoice_number
    end

    test "enforces unique ksef_number" do
      create_invoice()
      assert {:error, changeset} = Invoices.create_invoice(@valid_attrs)
      assert "has already been taken" in errors_on(changeset).ksef_number
    end
  end

  describe "upsert_invoice/1" do
    test "inserts new invoice" do
      assert {:ok, %Invoice{}} = Invoices.upsert_invoice(@valid_attrs)
    end

    test "updates existing invoice on ksef_number conflict" do
      {:ok, original} = Invoices.upsert_invoice(@valid_attrs)

      {:ok, updated} =
        Invoices.upsert_invoice(%{@valid_attrs | seller_name: "Updated Name"})

      assert updated.id == original.id
      assert updated.seller_name == "Updated Name"
    end
  end

  describe "list_invoices/1" do
    test "returns all invoices" do
      create_invoice()
      assert [%Invoice{}] = Invoices.list_invoices()
    end

    test "filters by type" do
      create_invoice(%{ksef_number: "inc-1", type: "income"})
      create_invoice(%{ksef_number: "exp-1", type: "expense"})

      assert [%{type: "income"}] = Invoices.list_invoices(%{type: "income"})
      assert [%{type: "expense"}] = Invoices.list_invoices(%{type: "expense"})
    end

    test "filters by status" do
      inv = create_invoice(%{type: "expense"})
      Invoices.approve_invoice(inv)

      assert [%{status: "approved"}] = Invoices.list_invoices(%{status: "approved"})
      assert [] = Invoices.list_invoices(%{status: "rejected"})
    end

    test "filters by date range" do
      create_invoice(%{ksef_number: "d-1", issue_date: ~D[2025-01-01]})
      create_invoice(%{ksef_number: "d-2", issue_date: ~D[2025-06-15]})

      result = Invoices.list_invoices(%{date_from: ~D[2025-06-01], date_to: ~D[2025-06-30]})
      assert length(result) == 1
      assert hd(result).ksef_number == "d-2"
    end

    test "filters by seller_nip" do
      create_invoice(%{ksef_number: "s-1", seller_nip: "1111111111"})
      create_invoice(%{ksef_number: "s-2", seller_nip: "2222222222"})

      assert [%{seller_nip: "1111111111"}] = Invoices.list_invoices(%{seller_nip: "1111111111"})
    end

    test "searches by query" do
      create_invoice(%{ksef_number: "q-1", buyer_name: "Acme Corp"})
      create_invoice(%{ksef_number: "q-2", buyer_name: "Widget Inc"})

      assert [%{buyer_name: "Acme Corp"}] = Invoices.list_invoices(%{query: "Acme"})
    end
  end

  describe "approve_invoice/1" do
    test "approves an expense invoice" do
      inv = create_invoice(%{type: "expense"})
      assert {:ok, %Invoice{status: "approved"}} = Invoices.approve_invoice(inv)
    end

    test "rejects approving an income invoice" do
      inv = create_invoice(%{type: "income"})
      assert {:error, {:invalid_type, "income"}} = Invoices.approve_invoice(inv)
    end
  end

  describe "reject_invoice/1" do
    test "rejects an expense invoice" do
      inv = create_invoice(%{type: "expense"})
      assert {:ok, %Invoice{status: "rejected"}} = Invoices.reject_invoice(inv)
    end

    test "rejects rejecting an income invoice" do
      inv = create_invoice(%{type: "income"})
      assert {:error, {:invalid_type, "income"}} = Invoices.reject_invoice(inv)
    end
  end

  describe "count_by_type_and_status/0" do
    test "returns counts grouped by type and status" do
      create_invoice(%{ksef_number: "c-1", type: "income"})
      create_invoice(%{ksef_number: "c-2", type: "expense"})

      counts = Invoices.count_by_type_and_status()
      assert counts[{"income", "pending"}] == 1
      assert counts[{"expense", "pending"}] == 1
    end
  end
end
