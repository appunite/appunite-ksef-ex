defmodule KsefHub.PaymentRequests.CsvBuilderTest do
  use ExUnit.Case, async: true

  alias KsefHub.PaymentRequests.CsvBuilder
  alias KsefHub.PaymentRequests.PaymentRequest

  @bom <<0xEF, 0xBB, 0xBF>>

  describe "build/1" do
    test "produces CSV with BOM header and Polish bank headers" do
      csv = CsvBuilder.build([])
      assert String.starts_with?(csv, @bom)
      assert csv =~ "Nazwa odbiorcy"
      assert csv =~ "Nr rachunku (IBAN)"
      assert csv =~ "Kwota"
      assert csv =~ "Waluta"
      assert csv =~ "Tytul"
    end

    test "includes payment request data" do
      pr = %PaymentRequest{
        recipient_name: "Dostawca Sp. z o.o.",
        recipient_address: %{
          street: "ul. Testowa 1",
          city: "Warszawa",
          postal_code: "00-001",
          country: "PL"
        },
        iban: "PL61109010140000071219812874",
        amount: Decimal.new("1230.00"),
        currency: "PLN",
        title: "Invoice FV/2026/001"
      }

      csv = CsvBuilder.build([pr])
      assert csv =~ "Dostawca Sp. z o.o."
      assert csv =~ "PL61109010140000071219812874"
      assert csv =~ "1230.00"
      assert csv =~ "PLN"
      assert csv =~ "Invoice FV/2026/001"
    end

    test "escapes fields with commas" do
      pr = %PaymentRequest{
        recipient_name: "Company, Inc.",
        recipient_address: nil,
        iban: "PL61109010140000071219812874",
        amount: Decimal.new("100.00"),
        currency: "PLN",
        title: "Test"
      }

      csv = CsvBuilder.build([pr])
      assert csv =~ ~s("Company, Inc.")
    end

    test "sanitizes formula injection" do
      pr = %PaymentRequest{
        recipient_name: "=DANGEROUS",
        recipient_address: nil,
        iban: "PL61109010140000071219812874",
        amount: Decimal.new("100.00"),
        currency: "PLN",
        title: "Test"
      }

      csv = CsvBuilder.build([pr])
      assert csv =~ "'=DANGEROUS"
    end

    test "uses CRLF line endings" do
      csv = CsvBuilder.build([])
      # Remove BOM first
      csv = String.replace_leading(csv, @bom, "")
      assert String.ends_with?(csv, "\r\n")
    end
  end
end
