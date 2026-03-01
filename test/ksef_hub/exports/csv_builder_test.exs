defmodule KsefHub.Exports.CsvBuilderTest do
  use ExUnit.Case, async: true

  alias KsefHub.Exports.CsvBuilder

  describe "build/1" do
    test "returns CSV with BOM and headers for empty list" do
      csv = CsvBuilder.build([])

      assert String.starts_with?(csv, <<0xEF, 0xBB, 0xBF>>)
      # Strip BOM
      content = String.replace_prefix(csv, <<0xEF, 0xBB, 0xBF>>, "")
      [header_line | _] = String.split(content, "\r\n", trim: true)

      assert header_line =~
               "Invoice Number,Issue Date,Type,Source,Status,Seller NIP,Seller Name,Buyer NIP,Buyer Name,Net Amount,VAT Amount,Gross Amount,Currency,Category,Tags,KSeF Number"
    end

    test "includes invoice data in correct columns" do
      invoice = build_invoice()
      csv = CsvBuilder.build([invoice])

      content = String.replace_prefix(csv, <<0xEF, 0xBB, 0xBF>>, "")
      lines = String.split(content, "\r\n", trim: true)

      assert length(lines) == 2
      [_header, data] = lines

      assert data =~ "FV/2026/001"
      assert data =~ "2026-01-15"
      assert data =~ "expense"
      assert data =~ "ksef"
      assert data =~ "pending"
      assert data =~ "1234567890"
      assert data =~ "Seller Corp"
      assert data =~ "0987654321"
      assert data =~ "Buyer Inc"
      assert data =~ "1000.00"
      assert data =~ "230.00"
      assert data =~ "1230.00"
      assert data =~ "PLN"
    end

    test "escapes fields containing commas" do
      invoice = build_invoice(%{seller_name: "Foo, Bar & Co."})
      csv = CsvBuilder.build([invoice])

      content = String.replace_prefix(csv, <<0xEF, 0xBB, 0xBF>>, "")
      assert content =~ ~s("Foo, Bar & Co.")
    end

    test "escapes fields containing double quotes" do
      invoice = build_invoice(%{seller_name: ~s(Foo "Bar" Corp)})
      csv = CsvBuilder.build([invoice])

      content = String.replace_prefix(csv, <<0xEF, 0xBB, 0xBF>>, "")
      assert content =~ ~s("Foo ""Bar"" Corp")
    end

    test "formats category name" do
      invoice = build_invoice(%{category: %{name: "operations:rent"}})
      csv = CsvBuilder.build([invoice])

      content = String.replace_prefix(csv, <<0xEF, 0xBB, 0xBF>>, "")
      assert content =~ "operations:rent"
    end

    test "formats tags as semicolon-separated" do
      invoice = build_invoice(%{tags: [%{name: "recurring"}, %{name: "office"}]})
      csv = CsvBuilder.build([invoice])

      content = String.replace_prefix(csv, <<0xEF, 0xBB, 0xBF>>, "")
      assert content =~ "recurring; office"
    end

    test "handles nil fields gracefully" do
      invoice = build_invoice(%{invoice_number: nil, net_amount: nil, issue_date: nil})
      csv = CsvBuilder.build([invoice])

      # Should not crash
      assert is_binary(csv)
    end

    test "handles multiple invoices" do
      invoices = [build_invoice(), build_invoice(%{invoice_number: "FV/2026/002"})]
      csv = CsvBuilder.build(invoices)

      content = String.replace_prefix(csv, <<0xEF, 0xBB, 0xBF>>, "")
      lines = String.split(content, "\r\n", trim: true)
      assert length(lines) == 3
    end
  end

  @spec build_invoice(map()) :: map()
  defp build_invoice(overrides \\ %{}) do
    defaults = %{
      invoice_number: "FV/2026/001",
      issue_date: ~D[2026-01-15],
      type: :expense,
      source: :ksef,
      status: :pending,
      seller_nip: "1234567890",
      seller_name: "Seller Corp",
      buyer_nip: "0987654321",
      buyer_name: "Buyer Inc",
      net_amount: Decimal.new("1000.00"),
      vat_amount: Decimal.new("230.00"),
      gross_amount: Decimal.new("1230.00"),
      currency: "PLN",
      category: nil,
      tags: [],
      ksef_number: nil
    }

    struct!(KsefHub.Invoices.Invoice, Map.merge(defaults, overrides))
  end
end
