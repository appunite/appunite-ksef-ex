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
      # Build XML with only P_13_2 and P_14_2 (8% rate), no 23% fields
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
        <Naglowek>
          <KodFormularza kodSystemowy="FA (3)" wersjaSchemy="1-0E">FA</KodFormularza>
          <WariantFormularza>3</WariantFormularza>
          <DataWytworzeniaFa>2025-03-01T09:00:00</DataWytworzeniaFa>
          <SystemInfo>Test</SystemInfo>
        </Naglowek>
        <Podmiot1>
          <DaneIdentyfikacyjne>
            <NIP>1111111111</NIP>
            <Nazwa>Seller</Nazwa>
          </DaneIdentyfikacyjne>
          <Adres><KodKraju>PL</KodKraju><AdresL1>ul. A 1</AdresL1><AdresL2>00-001 W</AdresL2></Adres>
        </Podmiot1>
        <Podmiot2>
          <DaneIdentyfikacyjne>
            <NIP>2222222222</NIP>
            <Nazwa>Buyer</Nazwa>
          </DaneIdentyfikacyjne>
          <Adres><KodKraju>PL</KodKraju><AdresL1>ul. B 2</AdresL1><AdresL2>00-002 W</AdresL2></Adres>
        </Podmiot2>
        <Fa>
          <KodWaluty>PLN</KodWaluty>
          <P_1>2025-03-01</P_1>
          <P_2>FV/8PCT/001</P_2>
          <P_13_2>800.00</P_13_2>
          <P_14_2>64.00</P_14_2>
          <P_15>864.00</P_15>
          <Adnotacje>
            <P_16>2</P_16><P_17>2</P_17><P_18>2</P_18><P_18A>2</P_18A>
            <Zwolnienie><P_19N>1</P_19N></Zwolnienie>
            <NoweSrodkiTransportu><P_22N>1</P_22N></NoweSrodkiTransportu>
            <P_23>2</P_23>
            <PMarzy><P_PMarzyN>1</P_PMarzyN></PMarzy>
          </Adnotacje>
          <FaWiersz>
            <NrWierszaFa>1</NrWierszaFa>
            <P_7>Item at 8%</P_7>
            <P_8A>szt.</P_8A>
            <P_8B>1</P_8B>
            <P_9A>800.00</P_9A>
            <P_11>800.00</P_11>
            <P_12>8</P_12>
          </FaWiersz>
        </Fa>
      </Faktura>
      """

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
