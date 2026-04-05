defmodule KsefHub.PaymentRequests.CsvBuilderTest do
  use ExUnit.Case, async: true

  alias KsefHub.PaymentRequests.CsvBuilder
  alias KsefHub.PaymentRequests.PaymentRequest

  @bom <<0xEF, 0xBB, 0xBF>>
  @orderer_iban "PL12105015201000009032123698"

  @expected_header "kwota,nazwa_kontrahenta,rachunek_kontrahenta,rachunek_zleceniodawcy,szczegóły_płatności,adres_1,adres_2"

  describe "build/2" do
    test "produces CSV with BOM and exact header line" do
      csv = CsvBuilder.build([], @orderer_iban)
      assert String.starts_with?(csv, @bom)
      [header | _] = csv |> strip_bom() |> split_lines()
      assert header == @expected_header
    end

    test "outputs amount in cents (multiplied by 100)" do
      pr = build_pr(amount: Decimal.new("9225.00"))
      [_header, row] = pr |> build_and_split()
      assert field(row, 0) == "922500"
    end

    test "rounds fractional cents correctly" do
      pr = build_pr(amount: Decimal.new("10.005"))
      [_header, row] = pr |> build_and_split()
      assert field(row, 0) == "1001"
    end

    test "produces exact row with all fields in correct positions" do
      pr =
        build_pr(
          amount: Decimal.new("1230.00"),
          recipient_name: "Dostawca Sp. z o.o.",
          recipient_nip: "1234567890",
          iban: "PL61109010140000071219812874",
          title: "FV/2026/001",
          recipient_address: %{
            street: "ul. Testowa 1",
            city: "Warszawa",
            postal_code: "00-001",
            country: "PL"
          }
        )

      [_header, row] = pr |> build_and_split()

      assert row ==
               "123000,Dostawca Sp. z o.o.,PL61109010140000071219812874,#{@orderer_iban},/NIP/1234567890/FV/2026/001,ul. Testowa 1,00-001 Warszawa"
    end

    test "includes orderer IBAN in correct position" do
      pr = build_pr()
      [_header, row] = pr |> build_and_split()
      assert field(row, 3) == @orderer_iban
    end

    test "formats payment details with /NIP/ prefix when NIP present" do
      pr = build_pr(recipient_nip: "6312700302", title: "39/03/2026")
      [_header, row] = pr |> build_and_split()
      assert field(row, 4) == "/NIP/6312700302/39/03/2026"
    end

    test "uses just title when recipient_nip is nil" do
      pr = build_pr(recipient_nip: nil, title: "39/03/2026")
      [_header, row] = pr |> build_and_split()
      assert field(row, 4) == "39/03/2026"
    end

    test "uses just title when recipient_nip is empty" do
      pr = build_pr(recipient_nip: "", title: "FV/001")
      [_header, row] = pr |> build_and_split()
      assert field(row, 4) == "FV/001"
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

      [_header, row] = pr |> build_and_split()
      assert field(row, 5) == "ul. Piwna 10"
      assert field(row, 6) == "44-100 Gliwice"
    end

    test "handles nil address gracefully" do
      pr = build_pr(recipient_address: nil)
      [_header, row] = pr |> build_and_split()
      assert field(row, 5) == ""
      assert field(row, 6) == ""
    end

    test "strips commas and quotes from fields" do
      pr = build_pr(recipient_name: "Company, Inc.")
      [_header, row] = pr |> build_and_split()
      assert field(row, 1) == "Company Inc."
    end

    test "strips commas from address fields" do
      pr =
        build_pr(
          recipient_address: %{
            street: "Warszawa, ODROWĄŻA 15",
            city: "Warszawa",
            postal_code: "03-310"
          }
        )

      [_header, row] = pr |> build_and_split()
      assert field(row, 5) == "Warszawa ODROWĄŻA 15"
    end

    test "sanitizes formula injection" do
      pr = build_pr(recipient_name: "=DANGEROUS")
      csv = CsvBuilder.build([pr], @orderer_iban)
      assert csv =~ "'=DANGEROUS"
    end

    test "uses CRLF line endings" do
      csv = CsvBuilder.build([], @orderer_iban)
      csv = strip_bom(csv)
      assert String.ends_with?(csv, "\r\n")
    end

    test "empty list produces header-only CSV" do
      lines = CsvBuilder.build([], @orderer_iban) |> strip_bom() |> split_lines()
      assert length(lines) == 1
      assert hd(lines) == @expected_header
    end

    test "multiple payment requests produce multiple data rows" do
      pr1 = build_pr(recipient_name: "Firma A", recipient_nip: "1111111111")
      pr2 = build_pr(recipient_name: "Firma B", recipient_nip: "2222222222")
      lines = CsvBuilder.build([pr1, pr2], @orderer_iban) |> strip_bom() |> split_lines()
      assert length(lines) == 3
      assert field(Enum.at(lines, 1), 1) == "Firma A"
      assert field(Enum.at(lines, 2), 1) == "Firma B"
    end

    test "address with only postal code, no city" do
      pr = build_pr(recipient_address: %{street: "ul. Krótka 5", postal_code: "00-100"})
      [_header, row] = pr |> build_and_split()
      assert field(row, 6) == "00-100"
    end

    test "address with only city, no postal code" do
      pr = build_pr(recipient_address: %{street: "Main St", city: "Kraków"})
      [_header, row] = pr |> build_and_split()
      assert field(row, 6) == "Kraków"
    end
  end

  # --- Helpers ---

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

  @spec build_and_split(PaymentRequest.t()) :: [String.t()]
  defp build_and_split(pr) do
    CsvBuilder.build([pr], @orderer_iban) |> strip_bom() |> split_lines()
  end

  @spec strip_bom(binary()) :: String.t()
  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(s), do: s

  @spec split_lines(String.t()) :: [String.t()]
  defp split_lines(csv), do: csv |> String.trim() |> String.split("\r\n")

  @spec field(String.t(), non_neg_integer()) :: String.t()
  defp field(row, index) do
    # Simple CSV field extraction — doesn't handle quoted commas but sufficient
    # for test data without commas in unquoted fields
    row |> String.split(",") |> Enum.at(index)
  end
end
