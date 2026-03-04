defmodule KsefHub.Exports.CsvBuilderTest do
  use ExUnit.Case, async: true

  alias KsefHub.Exports.CsvBuilder
  alias KsefHub.Invoices.{Category, Invoice, Tag}

  describe "build/1" do
    test "returns CSV with BOM and headers for empty list" do
      csv = CsvBuilder.build([])

      assert String.starts_with?(csv, <<0xEF, 0xBB, 0xBF>>)
      # Strip BOM
      content = String.replace_prefix(csv, <<0xEF, 0xBB, 0xBF>>, "")
      [header_line | _] = String.split(content, "\r\n", trim: true)

      assert header_line ==
               "Invoice Number,Issue Date,Sales Date,Due Date,Type,Source,Seller NIP,Seller Name,Seller Address,Buyer NIP,Buyer Name,Buyer Address,Net Amount,Gross Amount,Currency,IBAN,Purchase Order,Category,Tags,KSeF Number,Added At,Original Filename,Duplicate Status"
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
      assert data =~ "1234567890"
      assert data =~ "Seller Corp"
      assert data =~ "0987654321"
      assert data =~ "Buyer Inc"
      assert data =~ "1000.00"
      assert data =~ "1230.00"
      assert data =~ "PLN"
      assert data =~ "2026-01-10 09:00"
      assert data =~ "invoice.pdf"
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
      invoice = build_invoice(%{category: %Category{name: "operations:rent"}})
      csv = CsvBuilder.build([invoice])

      content = String.replace_prefix(csv, <<0xEF, 0xBB, 0xBF>>, "")
      assert content =~ "operations:rent"
    end

    test "formats tags as semicolon-separated" do
      invoice = build_invoice(%{tags: [%Tag{name: "recurring"}, %Tag{name: "office"}]})
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

    test "includes extraction fields at correct column positions" do
      invoice =
        build_invoice(%{
          sales_date: ~D[2026-01-14],
          due_date: ~D[2026-02-14],
          iban: "PL61109010140000071219812874",
          purchase_order: "PO-CSV-001",
          seller_address: %{"street" => "ul. Testowa 1", "city" => "Warszawa", "country" => "PL"},
          buyer_address: %{"street" => "ul. Kupna 5", "city" => "Kraków", "country" => "PL"}
        })

      csv = CsvBuilder.build([invoice])
      content = String.replace_prefix(csv, <<0xEF, 0xBB, 0xBF>>, "")
      [_header, data_line | _] = String.split(content, "\r\n", trim: true)
      cols = parse_csv_row(data_line)

      # Column indices based on header order
      assert Enum.at(cols, 2) == "2026-01-14"
      assert Enum.at(cols, 3) == "2026-02-14"
      assert Enum.at(cols, 15) == "PL61109010140000071219812874"
      assert Enum.at(cols, 16) == "PO-CSV-001"
      assert Enum.at(cols, 8) =~ "ul. Testowa 1"
      assert Enum.at(cols, 11) =~ "ul. Kupna 5"
    end
  end

  @spec build_invoice(map()) :: Invoice.t()
  defp build_invoice(overrides \\ %{}) do
    defaults = %{
      invoice_number: "FV/2026/001",
      issue_date: ~D[2026-01-15],
      type: :expense,
      source: :ksef,
      status: :approved,
      seller_nip: "1234567890",
      seller_name: "Seller Corp",
      buyer_nip: "0987654321",
      buyer_name: "Buyer Inc",
      net_amount: Decimal.new("1000.00"),
      gross_amount: Decimal.new("1230.00"),
      currency: "PLN",
      category: nil,
      tags: [],
      ksef_number: nil,
      inserted_at: ~N[2026-01-10 09:00:00],
      original_filename: "invoice.pdf",
      duplicate_status: nil,
      sales_date: nil,
      due_date: nil,
      iban: nil,
      purchase_order: nil,
      seller_address: nil,
      buyer_address: nil
    }

    struct!(Invoice, Map.merge(defaults, overrides))
  end

  # Simple CSV row parser that handles quoted fields with commas.
  @spec parse_csv_row(String.t()) :: [String.t()]
  defp parse_csv_row(row) do
    ~r/(?:\"([^\"]*(?:\"\"[^\"]*)*)\"|([^,]*))(,|$)/
    |> Regex.scan(row)
    |> Enum.map(fn
      [_, quoted, "", _] -> String.replace(quoted, ~s(""), ~s("))
      [_, "", unquoted, _] -> unquoted
      [_, "", "", _] -> ""
    end)
  end
end
