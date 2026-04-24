defmodule KsefHub.Exports.CsvBuilderTest do
  use ExUnit.Case, async: true

  alias KsefHub.Exports.CsvBuilder
  alias KsefHub.Invoices.{Category, Invoice}
  alias KsefHub.PaymentRequests.PaymentRequest

  describe "build/2" do
    test "returns CSV with BOM and headers for empty list" do
      csv = CsvBuilder.build([])

      assert String.starts_with?(csv, <<0xEF, 0xBB, 0xBF>>)
      [header_line | _] = csv_lines(csv)

      assert header_line =~ "Invoice Number;"
      assert header_line =~ "Billing Period;"
      assert header_line =~ "Status;"
      assert header_line =~ "Note;"
      assert header_line =~ "Added By;"
      assert header_line =~ "Updated At;"
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

    test "does not quote fields containing only commas (semicolon is the delimiter)" do
      invoice = build_invoice(%{seller_name: "Foo, Bar & Co."})
      assert csv_content(invoice) =~ "Foo, Bar & Co."
      refute csv_content(invoice) =~ ~s("Foo, Bar & Co.")
    end

    test "escapes fields containing semicolons" do
      invoice = build_invoice(%{seller_name: "Dept; Finance"})
      assert csv_content(invoice) =~ ~s("Dept; Finance")
    end

    test "escapes fields containing double quotes" do
      invoice = build_invoice(%{seller_name: ~s(Foo "Bar" Corp)})
      assert csv_content(invoice) =~ ~s("Foo ""Bar"" Corp")
    end

    test "formats category name" do
      invoice = build_invoice(%{category: %Category{name: "operations:rent"}})
      assert csv_content(invoice) =~ "operations:rent"
    end

    test "formats tags as comma-separated" do
      invoice = build_invoice(%{tags: ["recurring", "office"]})
      assert csv_content(invoice) =~ "recurring, office"
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

    test "standard mode does not include extended headers" do
      csv = CsvBuilder.build([])
      [header_line | _] = csv_lines(csv)

      refute header_line =~ "Invoice ID"
      refute header_line =~ "Company ID"
      refute header_line =~ "Cost Line"
      refute header_line =~ "Prediction Status"
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

  describe "build/2 extended mode" do
    test "includes extended headers" do
      csv = CsvBuilder.build([], extended: true)
      [header_line | _] = csv_lines(csv)

      assert header_line =~ "Invoice ID"
      assert header_line =~ "Company ID"
      assert header_line =~ "Cost Line"
      assert header_line =~ "Project Tag"
      assert header_line =~ "Is Excluded"
      assert header_line =~ "Access Restricted"
      assert header_line =~ "Payment Status"
      assert header_line =~ "Payment Date"
      assert header_line =~ "Category Identifier"
      assert header_line =~ "Prediction Status"
      assert header_line =~ "Predicted Category"
      assert header_line =~ "Predicted Tag"
      assert header_line =~ "Category Confidence %"
      assert header_line =~ "Tag Confidence %"
      assert header_line =~ "Extraction Status"
    end

    test "includes extended fields in data rows" do
      invoice =
        build_invoice(%{
          id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
          company_id: "11111111-2222-3333-4444-555555555555",
          expense_cost_line: :service,
          project_tag: "project-alpha",
          is_excluded: true,
          access_restricted: false,
          prediction_status: :predicted,
          prediction_expense_category_name: "operations:rent",
          prediction_expense_tag_name: "recurring",
          prediction_expense_category_confidence: 0.923,
          prediction_expense_tag_confidence: 0.871,
          extraction_status: :complete,
          category: %Category{name: "Rent", identifier: "operations:rent"},
          payment_requests: [
            %PaymentRequest{status: :paid, paid_at: ~U[2026-02-01 10:00:00Z]}
          ]
        })

      cols = csv_cols(invoice, extended: true)

      # Extended fields start after standard columns (32 standard)
      assert Enum.at(cols, 32) == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
      assert Enum.at(cols, 33) == "11111111-2222-3333-4444-555555555555"
      assert Enum.at(cols, 34) == "service"
      assert Enum.at(cols, 35) == "project-alpha"
      assert Enum.at(cols, 36) == "true"
      assert Enum.at(cols, 37) == "false"
      assert Enum.at(cols, 38) == "paid"
      assert Enum.at(cols, 39) == "2026-02-01 10:00"
      assert Enum.at(cols, 40) == "operations:rent"
      assert Enum.at(cols, 41) == "predicted"
      assert Enum.at(cols, 42) == "operations:rent"
      assert Enum.at(cols, 43) == "recurring"
      assert Enum.at(cols, 44) == "92.3"
      assert Enum.at(cols, 45) == "87.1"
      assert Enum.at(cols, 46) == "complete"
    end

    test "handles nil payment_requests gracefully" do
      invoice = build_invoice(%{payment_requests: []})
      cols = csv_cols(invoice, extended: true)

      assert Enum.at(cols, 38) == ""
      assert Enum.at(cols, 39) == ""
    end

    test "shows pending payment when no paid request exists" do
      invoice =
        build_invoice(%{
          payment_requests: [%PaymentRequest{status: :pending, paid_at: nil}]
        })

      cols = csv_cols(invoice, extended: true)

      assert Enum.at(cols, 38) == "pending"
      assert Enum.at(cols, 39) == ""
    end

    test "prefers paid payment request over pending" do
      invoice =
        build_invoice(%{
          payment_requests: [
            %PaymentRequest{status: :pending, paid_at: nil},
            %PaymentRequest{status: :paid, paid_at: ~U[2026-03-01 12:00:00Z]}
          ]
        })

      cols = csv_cols(invoice, extended: true)

      assert Enum.at(cols, 38) == "paid"
      assert Enum.at(cols, 39) == "2026-03-01 12:00"
    end

    test "formats confidence as percentage with one decimal" do
      invoice =
        build_invoice(%{
          prediction_expense_category_confidence: 0.716,
          prediction_expense_tag_confidence: 0.5
        })

      cols = csv_cols(invoice, extended: true)

      assert Enum.at(cols, 44) == "71.6"
      assert Enum.at(cols, 45) == "50.0"
    end

    test "handles nil prediction fields" do
      invoice =
        build_invoice(%{
          prediction_status: nil,
          prediction_expense_category_confidence: nil,
          prediction_expense_tag_confidence: nil
        })

      cols = csv_cols(invoice, extended: true)

      assert Enum.at(cols, 41) == ""
      assert Enum.at(cols, 44) == ""
      assert Enum.at(cols, 45) == ""
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

  @spec csv_cols(Invoice.t(), keyword()) :: [String.t()]
  defp csv_cols(invoice, opts \\ []) do
    extended = Keyword.get(opts, :extended, false)

    content =
      [invoice]
      |> CsvBuilder.build(extended: extended)
      |> String.replace_prefix(<<0xEF, 0xBB, 0xBF>>, "")

    [_header, data_line | _] = String.split(content, "\r\n", trim: true)
    parse_csv_row(data_line)
  end

  @spec csv_col(Invoice.t(), non_neg_integer()) :: String.t()
  defp csv_col(invoice, index), do: Enum.at(csv_cols(invoice), index)

  @spec build_invoice(map()) :: Invoice.t()
  defp build_invoice(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      company_id: Ecto.UUID.generate(),
      invoice_number: "FV/2026/001",
      issue_date: ~D[2026-01-15],
      type: :expense,
      source: :ksef,
      expense_approval_status: :approved,
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
      inbound_email: nil,
      invoice_kind: :vat,
      corrected_invoice_number: nil,
      corrected_invoice_ksef_number: nil,
      correction_reason: nil,
      expense_cost_line: nil,
      project_tag: nil,
      is_excluded: false,
      access_restricted: false,
      prediction_status: nil,
      prediction_expense_category_name: nil,
      prediction_expense_tag_name: nil,
      prediction_expense_category_confidence: nil,
      prediction_expense_tag_confidence: nil,
      extraction_status: nil,
      payment_requests: []
    }

    struct!(Invoice, Map.merge(defaults, overrides))
  end

  # Simple CSV row parser that handles quoted fields with semicolons.
  @spec parse_csv_row(String.t()) :: [String.t()]
  defp parse_csv_row(row) do
    ~r/(?:\"([^\"]*(?:\"\"[^\"]*)*)\"|([^;]*))(;|$)/
    |> Regex.scan(row)
    |> Enum.map(fn
      [_, quoted, "", _] -> String.replace(quoted, ~s(""), ~s("))
      [_, "", unquoted, _] -> unquoted
      [_, "", "", _] -> ""
    end)
  end
end
