defmodule KsefHub.Exports.CsvBuilderTest do
  use ExUnit.Case, async: true

  alias KsefHub.Exports.CsvBuilder
  alias KsefHub.Invoices.{Category, Invoice, Tag}

  describe "build/1" do
    test "returns CSV with BOM and headers for empty list" do
      csv = CsvBuilder.build([])

      assert String.starts_with?(csv, <<0xEF, 0xBB, 0xBF>>)
      [header_line | _] = csv_lines(csv)

      assert header_line =~ "Invoice Number,"
      assert header_line =~ "Billing Period,"
      assert header_line =~ "Status,"
      assert header_line =~ "Note,"
      assert header_line =~ "Added By,"
      assert header_line =~ "Updated At,"
    end

    test "includes invoice data in correct columns" do
      invoice = build_invoice()
      csv = CsvBuilder.build([invoice])
      lines = csv_lines(csv)

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
      assert csv_content(invoice) =~ ~s("Foo, Bar & Co.")
    end

    test "escapes fields containing double quotes" do
      invoice = build_invoice(%{seller_name: ~s(Foo "Bar" Corp)})
      assert csv_content(invoice) =~ ~s("Foo ""Bar"" Corp")
    end

    test "formats category name" do
      invoice = build_invoice(%{category: %Category{name: "operations:rent"}})
      assert csv_content(invoice) =~ "operations:rent"
    end

    test "formats tags as semicolon-separated" do
      invoice = build_invoice(%{tags: [%Tag{name: "recurring"}, %Tag{name: "office"}]})
      assert csv_content(invoice) =~ "recurring; office"
    end

    test "includes Added By from created_by user" do
      user = %KsefHub.Accounts.User{name: "Jan Kowalski", email: "jan@example.com"}
      invoice = build_invoice(%{source: :manual, created_by: user})

      assert csv_col(invoice, 24) == "Jan Kowalski (manual)"
    end

    test "includes Added By as KSeF for synced invoices" do
      invoice = build_invoice(%{source: :ksef})

      assert csv_col(invoice, 24) == "KSeF (automatic sync)"
    end

    test "includes billing period, status, and note columns" do
      invoice =
        build_invoice(%{
          billing_date_from: ~D[2026-01-01],
          billing_date_to: ~D[2026-01-01],
          note: "Monthly rent"
        })

      assert csv_col(invoice, 4) == "2026-01"
      assert csv_col(invoice, 6) == "approved"
      assert csv_col(invoice, 21) == "Monthly rent"
    end

    test "handles nil fields gracefully" do
      invoice = build_invoice(%{invoice_number: nil, net_amount: nil, issue_date: nil})
      csv = CsvBuilder.build([invoice])

      assert is_binary(csv)
    end

    test "handles multiple invoices" do
      invoices = [build_invoice(), build_invoice(%{invoice_number: "FV/2026/002"})]
      assert length(csv_lines(CsvBuilder.build(invoices))) == 3
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

      cols = csv_cols(invoice)

      assert Enum.at(cols, 2) == "2026-01-14"
      assert Enum.at(cols, 3) == "2026-02-14"
      assert Enum.at(cols, 17) == "PL61109010140000071219812874"
      assert Enum.at(cols, 18) == "PO-CSV-001"
      assert Enum.at(cols, 10) =~ "ul. Testowa 1"
      assert Enum.at(cols, 13) =~ "ul. Kupna 5"
    end
  end

  @spec csv_lines(binary()) :: [String.t()]
  defp csv_lines(csv) do
    csv
    |> String.replace_prefix(<<0xEF, 0xBB, 0xBF>>, "")
    |> String.split("\r\n", trim: true)
  end

  @spec csv_content(Invoice.t()) :: String.t()
  defp csv_content(invoice) do
    [invoice] |> CsvBuilder.build() |> String.replace_prefix(<<0xEF, 0xBB, 0xBF>>, "")
  end

  @spec csv_cols(Invoice.t()) :: [String.t()]
  defp csv_cols(invoice) do
    [_header, data_line | _] = invoice |> csv_content() |> String.split("\r\n", trim: true)
    parse_csv_row(data_line)
  end

  @spec csv_col(Invoice.t(), non_neg_integer()) :: String.t()
  defp csv_col(invoice, index), do: Enum.at(csv_cols(invoice), index)

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
      buyer_address: nil,
      billing_date_from: nil,
      billing_date_to: nil,
      note: nil,
      updated_at: ~N[2026-01-10 09:00:00],
      created_by: nil,
      inbound_email: nil
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
