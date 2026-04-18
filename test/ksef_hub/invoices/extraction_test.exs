defmodule KsefHub.Invoices.ExtractionTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invoices

  setup do
    company = insert(:company)
    %{company: company}
  end

  describe "determine_extraction_status_from_attrs/1" do
    test "returns :complete when all critical fields are present" do
      attrs = %{
        seller_nip: "1234567890",
        seller_name: "Seller",
        invoice_number: "FV/001",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100"),
        gross_amount: Decimal.new("123")
      }

      assert Invoices.determine_extraction_status_from_attrs(attrs) == :complete
    end

    test "returns :partial when net_amount is missing" do
      attrs = %{
        seller_nip: "1234567890",
        seller_name: "Seller",
        invoice_number: "FV/001",
        issue_date: ~D[2026-01-01],
        net_amount: nil,
        gross_amount: Decimal.new("123")
      }

      assert Invoices.determine_extraction_status_from_attrs(attrs) == :partial
    end

    test "returns :partial when gross_amount is missing" do
      attrs = %{
        seller_nip: "1234567890",
        seller_name: "Seller",
        invoice_number: "FV/001",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100"),
        gross_amount: nil
      }

      assert Invoices.determine_extraction_status_from_attrs(attrs) == :partial
    end

    test "returns :partial when seller_nip is missing" do
      attrs = %{
        seller_nip: nil,
        seller_name: "Seller",
        invoice_number: "FV/001",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100"),
        gross_amount: Decimal.new("123")
      }

      assert Invoices.determine_extraction_status_from_attrs(attrs) == :partial
    end

    test "returns :partial when invoice_number is missing" do
      attrs = %{
        seller_nip: "1234567890",
        seller_name: "Seller",
        invoice_number: nil,
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100"),
        gross_amount: Decimal.new("123")
      }

      assert Invoices.determine_extraction_status_from_attrs(attrs) == :partial
    end

    test "treats whitespace-only strings as missing" do
      attrs = %{
        seller_nip: "   ",
        seller_name: "Seller",
        invoice_number: "FV/001",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100"),
        gross_amount: Decimal.new("123")
      }

      assert Invoices.determine_extraction_status_from_attrs(attrs) == :partial
    end

    test "treats LLM placeholder strings as missing" do
      for placeholder <- ["-", "--", "N/A", "n/a", "null", "`"] do
        attrs = %{
          seller_nip: placeholder,
          seller_name: "Seller",
          invoice_number: "FV/001",
          issue_date: ~D[2026-01-01],
          net_amount: Decimal.new("100"),
          gross_amount: Decimal.new("123")
        }

        assert Invoices.determine_extraction_status_from_attrs(attrs) == :partial,
               "expected :partial for placeholder #{inspect(placeholder)}"
      end
    end

    # get_extracted_decimal/2 converts LLM sentinel zeros to nil before this
    # function is called, so extraction always arrives here with nil for
    # unfound amounts. Decimal.new("0") can only reach this function via manual
    # edit — in that case, zero is treated as a valid (present) value.
    test "treats Decimal zero as present (manual-edit path)" do
      attrs = %{
        seller_nip: "1234567890",
        seller_name: "Seller",
        invoice_number: "FV/001",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("0"),
        gross_amount: Decimal.new("123")
      }

      assert Invoices.determine_extraction_status_from_attrs(attrs) == :complete
    end
  end

  describe "missing_critical_fields/1" do
    test "returns empty list when all critical fields present", %{company: company} do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          seller_nip: "1234567890",
          seller_name: "Seller",
          invoice_number: "FV/001",
          issue_date: ~D[2026-02-20],
          net_amount: Decimal.new("100"),
          gross_amount: Decimal.new("123")
        )

      assert Invoices.missing_critical_fields(invoice) == []
    end

    test "returns missing fields", %{company: company} do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          seller_nip: nil,
          net_amount: nil
        )

      missing = Invoices.missing_critical_fields(invoice)
      assert :seller_nip in missing
      assert :net_amount in missing
      refute :seller_name in missing
    end
  end

  describe "recalculate_extraction_status/2" do
    test "returns complete when all critical fields present", %{company: company} do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :partial,
          seller_nip: "1234567890",
          seller_name: "Seller",
          invoice_number: "FV/001",
          issue_date: ~D[2026-02-20],
          net_amount: Decimal.new("100"),
          gross_amount: Decimal.new("123")
        )

      attrs = %{buyer_name: "Buyer"}
      result = Invoices.recalculate_extraction_status(invoice, attrs)
      assert result[:extraction_status] == :complete
    end

    test "returns partial when critical field is missing", %{company: company} do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :complete,
          seller_nip: "1234567890",
          seller_name: "Seller",
          invoice_number: "FV/001",
          issue_date: ~D[2026-02-20],
          net_amount: Decimal.new("100"),
          gross_amount: Decimal.new("123")
        )

      attrs = %{seller_nip: nil}
      result = Invoices.recalculate_extraction_status(invoice, attrs)
      assert result[:extraction_status] == :partial
    end

    test "treats empty string as missing field", %{company: company} do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :complete,
          seller_nip: "1234567890",
          seller_name: "Seller",
          invoice_number: "FV/001",
          issue_date: ~D[2026-02-20],
          net_amount: Decimal.new("100"),
          gross_amount: Decimal.new("123")
        )

      attrs = %{seller_nip: ""}
      result = Invoices.recalculate_extraction_status(invoice, attrs)
      assert result[:extraction_status] == :partial
    end
  end

  describe "compute_billing_date/1" do
    test "returns first of month from sales_date" do
      assert Invoices.compute_billing_date(%{sales_date: ~D[2026-07-23]}) == ~D[2026-07-01]
    end

    test "falls back to issue_date when no sales_date" do
      assert Invoices.compute_billing_date(%{issue_date: ~D[2026-11-05]}) == ~D[2026-11-01]
    end

    test "prefers sales_date over issue_date" do
      assert Invoices.compute_billing_date(%{
               sales_date: ~D[2026-02-15],
               issue_date: ~D[2026-01-30]
             }) == ~D[2026-02-01]
    end

    test "returns nil when neither date present" do
      assert Invoices.compute_billing_date(%{}) == nil
    end

    test "handles string keys" do
      assert Invoices.compute_billing_date(%{"sales_date" => ~D[2026-05-10]}) == ~D[2026-05-01]
    end

    test "handles string date values" do
      assert Invoices.compute_billing_date(%{issue_date: "2026-08-19"}) == ~D[2026-08-01]
    end

    test "handles ISO 8601 datetime strings" do
      assert Invoices.compute_billing_date(%{issue_date: "2026-03-15T10:30:00Z"}) ==
               ~D[2026-03-01]
    end

    test "handles invalid string date gracefully" do
      assert Invoices.compute_billing_date(%{issue_date: "not-a-date"}) == nil
    end
  end

  describe "populate_company_fields/2" do
    test "sets buyer fields for expense invoices", %{company: company} do
      attrs = %{type: :expense, seller_nip: "9999999999", seller_name: "Other Co"}
      result = Invoices.populate_company_fields(attrs, company)

      assert result.buyer_nip == company.nip
      assert result.buyer_name == company.name
      assert result.seller_nip == "9999999999"
    end

    test "sets seller fields for income invoices", %{company: company} do
      attrs = %{type: :income, buyer_nip: "9999999999", buyer_name: "Other Co"}
      result = Invoices.populate_company_fields(attrs, company)

      assert result.seller_nip == company.nip
      assert result.seller_name == company.name
      assert result.buyer_nip == "9999999999"
    end

    test "does not modify attrs for unknown type", %{company: company} do
      attrs = %{type: nil, seller_nip: "1111111111"}
      result = Invoices.populate_company_fields(attrs, company)

      assert result == attrs
    end

    test "handles string type 'expense'", %{company: company} do
      attrs = %{type: "expense", seller_nip: "9999999999", seller_name: "Other Co"}
      result = Invoices.populate_company_fields(attrs, company)

      assert result.buyer_nip == company.nip
      assert result.buyer_name == company.name
      assert result.seller_nip == "9999999999"
    end

    test "handles string type 'income'", %{company: company} do
      attrs = %{type: "income", buyer_nip: "9999999999", buyer_name: "Other Co"}
      result = Invoices.populate_company_fields(attrs, company)

      assert result.seller_nip == company.nip
      assert result.seller_name == company.name
      assert result.buyer_nip == "9999999999"
    end
  end
end
