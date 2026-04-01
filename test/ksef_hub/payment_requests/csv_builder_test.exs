defmodule KsefHub.PaymentRequests.CsvBuilderTest do
  use ExUnit.Case, async: true

  alias KsefHub.PaymentRequests.CsvBuilder
  alias KsefHub.PaymentRequests.PaymentRequest

  @bom <<0xEF, 0xBB, 0xBF>>
  @orderer_iban "PL12105015201000009032123698"

  describe "build/2" do
    test "produces CSV with BOM header and correct Polish bank headers" do
      csv = CsvBuilder.build([], @orderer_iban)
      assert String.starts_with?(csv, @bom)
      assert csv =~ "kwota"
      assert csv =~ "nazwa_kontrahenta"
      assert csv =~ "rachunek_kontrahenta"
      assert csv =~ "rachunek_zleceniodawcy"
      assert csv =~ "szczegóły_płatności"
      assert csv =~ "adres_1"
      assert csv =~ "adres_2"
    end

    test "outputs amount in cents (multiplied by 100)" do
      pr = build_pr(amount: Decimal.new("9225.00"))
      csv = CsvBuilder.build([pr], @orderer_iban)
      assert csv =~ "922500"
    end

    test "rounds fractional cents correctly" do
      pr = build_pr(amount: Decimal.new("10.005"))
      csv = CsvBuilder.build([pr], @orderer_iban)
      assert csv =~ "1001"
    end

    test "includes recipient name and IBAN" do
      pr = build_pr(recipient_name: "Hirewise Sp. z o.o.", iban: "PL12124013431111001109295999")
      csv = CsvBuilder.build([pr], @orderer_iban)
      assert csv =~ "Hirewise Sp. z o.o."
      assert csv =~ "PL12124013431111001109295999"
    end

    test "includes orderer IBAN in every row" do
      pr = build_pr()
      csv = CsvBuilder.build([pr], @orderer_iban)
      assert csv =~ @orderer_iban
    end

    test "formats payment details with /NIP/ prefix when NIP present" do
      pr = build_pr(recipient_nip: "6312700302", title: "39/03/2026")
      csv = CsvBuilder.build([pr], @orderer_iban)
      assert csv =~ "/NIP/6312700302/39/03/2026"
    end

    test "uses just title when recipient_nip is nil" do
      pr = build_pr(recipient_nip: nil, title: "39/03/2026")
      csv = CsvBuilder.build([pr], @orderer_iban)
      assert csv =~ "39/03/2026"
      refute csv =~ "/NIP/"
    end

    test "uses just title when recipient_nip is empty" do
      pr = build_pr(recipient_nip: "", title: "FV/001")
      csv = CsvBuilder.build([pr], @orderer_iban)
      assert csv =~ "FV/001"
      refute csv =~ "/NIP/"
    end

    test "splits address into adres_1 (street) and adres_2 (postal + city)" do
      pr =
        build_pr(
          recipient_address: %{
            street: "ul. Piwna 10",
            city: "Gliwice",
            postal_code: "44-100",
            country: "PL"
          }
        )

      csv = CsvBuilder.build([pr], @orderer_iban)
      assert csv =~ "ul. Piwna 10"
      assert csv =~ "44-100 Gliwice"
    end

    test "handles nil address gracefully" do
      pr = build_pr(recipient_address: nil)
      csv = CsvBuilder.build([pr], @orderer_iban)
      # Should still produce valid CSV with empty address fields
      assert String.starts_with?(csv, @bom)
    end

    test "escapes fields with commas" do
      pr = build_pr(recipient_name: "Company, Inc.")
      csv = CsvBuilder.build([pr], @orderer_iban)
      assert csv =~ ~s("Company, Inc.")
    end

    test "sanitizes formula injection" do
      pr = build_pr(recipient_name: "=DANGEROUS")
      csv = CsvBuilder.build([pr], @orderer_iban)
      assert csv =~ "'=DANGEROUS"
    end

    test "uses CRLF line endings" do
      csv = CsvBuilder.build([], @orderer_iban)
      csv = String.replace_leading(csv, @bom, "")
      assert String.ends_with?(csv, "\r\n")
    end

    test "empty list produces header-only CSV" do
      csv = CsvBuilder.build([], @orderer_iban)
      csv = String.replace_leading(csv, @bom, "")
      lines = csv |> String.trim() |> String.split("\r\n")
      assert length(lines) == 1
      assert hd(lines) =~ "kwota"
    end

    test "multiple payment requests produce multiple data rows" do
      pr1 = build_pr(recipient_name: "Firma A", recipient_nip: "1111111111")
      pr2 = build_pr(recipient_name: "Firma B", recipient_nip: "2222222222")
      csv = CsvBuilder.build([pr1, pr2], @orderer_iban)
      csv = String.replace_leading(csv, @bom, "")
      lines = csv |> String.trim() |> String.split("\r\n")
      assert length(lines) == 3
      assert Enum.at(lines, 1) =~ "Firma A"
      assert Enum.at(lines, 2) =~ "Firma B"
    end

    test "address with only postal code, no city" do
      pr = build_pr(recipient_address: %{street: "ul. Krótka 5", postal_code: "00-100"})
      csv = CsvBuilder.build([pr], @orderer_iban)
      assert csv =~ "00-100"
      refute csv =~ "00-100 "
    end

    test "address with only city, no postal code" do
      pr = build_pr(recipient_address: %{street: "Main St", city: "Kraków"})
      csv = CsvBuilder.build([pr], @orderer_iban)
      assert csv =~ "Kraków"
    end
  end

  @spec build_pr(keyword()) :: PaymentRequest.t()
  defp build_pr(overrides \\ []) do
    defaults = %{
      recipient_name: "Dostawca Sp. z o.o.",
      recipient_nip: "1234567890",
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

    struct(PaymentRequest, Map.merge(defaults, Map.new(overrides)))
  end
end
