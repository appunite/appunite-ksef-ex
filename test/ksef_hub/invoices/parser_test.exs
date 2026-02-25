defmodule KsefHub.Invoices.ParserTest do
  use ExUnit.Case, async: true

  alias KsefHub.Invoices.Parser

  @fixtures_path "test/support/fixtures"

  describe "parse/1" do
    test "extracts seller and buyer from income invoice" do
      xml = File.read!(Path.join(@fixtures_path, "sample_income.xml"))

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.seller_nip == "1234567890"
      assert invoice.seller_name == "Testowa Firma Sp. z o.o."
      assert invoice.buyer_nip == "0987654321"
      assert invoice.buyer_name == "Kupujący S.A."
    end

    test "extracts invoice number and date" do
      xml = File.read!(Path.join(@fixtures_path, "sample_income.xml"))

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.invoice_number == "FV/2025/001"
      assert invoice.issue_date == ~D[2025-01-15]
    end

    test "extracts amounts" do
      xml = File.read!(Path.join(@fixtures_path, "sample_income.xml"))

      assert {:ok, invoice} = Parser.parse(xml)
      assert Decimal.equal?(invoice.net_amount, Decimal.new("10000.00"))
      assert Decimal.equal?(invoice.vat_amount, Decimal.new("2300.00"))
      assert Decimal.equal?(invoice.gross_amount, Decimal.new("12300.00"))
    end

    test "extracts currency" do
      xml = File.read!(Path.join(@fixtures_path, "sample_income.xml"))

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.currency == "PLN"
    end

    test "parses line items" do
      xml = File.read!(Path.join(@fixtures_path, "sample_income.xml"))

      assert {:ok, invoice} = Parser.parse(xml)
      assert length(invoice.line_items) == 1

      [item] = invoice.line_items
      assert item.description == "Usługi programistyczne"
      assert item.unit == "szt."
      assert Decimal.equal?(item.quantity, Decimal.new("160"))
      assert Decimal.equal?(item.unit_price, Decimal.new("62.50"))
      assert Decimal.equal?(item.net_amount, Decimal.new("10000.00"))
    end

    test "parses multi-line expense invoice" do
      xml = File.read!(Path.join(@fixtures_path, "sample_expense.xml"))

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.seller_nip == "5555555555"
      assert invoice.buyer_nip == "1234567890"
      assert length(invoice.line_items) == 2

      [item1, item2] = invoice.line_items
      assert item1.description == "Hosting i infrastruktura"
      assert item2.description == "Licencje oprogramowania"
    end

    test "sums amounts across multiple VAT rate buckets" do
      xml = File.read!(Path.join(@fixtures_path, "sample_mixed_vat.xml"))

      assert {:ok, invoice} = Parser.parse(xml)
      # net = P_13_1 (1000) + P_13_2 (500) + P_13_3 (200) = 1700
      assert Decimal.equal?(invoice.net_amount, Decimal.new("1700.00"))
      # vat = P_14_1 (230) + P_14_2 (40) + P_14_3 (10) = 280
      assert Decimal.equal?(invoice.vat_amount, Decimal.new("280.00"))
      assert Decimal.equal?(invoice.gross_amount, Decimal.new("1980.00"))
    end

    test "parses invoice with only 8% VAT rate (no P_13_1)" do
      xml = File.read!(Path.join(@fixtures_path, "sample_8pct_vat.xml"))

      assert {:ok, invoice} = Parser.parse(xml)
      assert Decimal.equal?(invoice.net_amount, Decimal.new("800.00"))
      assert Decimal.equal?(invoice.vat_amount, Decimal.new("64.00"))
      assert Decimal.equal?(invoice.gross_amount, Decimal.new("864.00"))
    end

    test "returns error for invalid XML" do
      assert {:error, {:invalid_xml, _}} = Parser.parse("<not-valid>")
    end

    test "returns error for empty string" do
      assert {:error, {:invalid_xml, _}} = Parser.parse("")
    end
  end

  describe "determine_type/2" do
    test "returns income when our NIP is seller" do
      invoice = %{seller_nip: "1234567890", buyer_nip: "9999999999"}
      assert Parser.determine_type(invoice, "1234567890") == :income
    end

    test "returns expense when our NIP is buyer" do
      invoice = %{seller_nip: "9999999999", buyer_nip: "1234567890"}
      assert Parser.determine_type(invoice, "1234567890") == :expense
    end

    test "defaults to income when NIP not found" do
      invoice = %{seller_nip: "1111111111", buyer_nip: "2222222222"}
      assert Parser.determine_type(invoice, "3333333333") == :income
    end
  end
end
