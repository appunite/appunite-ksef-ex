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
      assert Decimal.equal?(invoice.gross_amount, Decimal.new("1980.00"))
    end

    test "parses invoice with only 8% VAT rate (no P_13_1)" do
      xml = File.read!(Path.join(@fixtures_path, "sample_8pct_vat.xml"))

      assert {:ok, invoice} = Parser.parse(xml)
      assert Decimal.equal?(invoice.net_amount, Decimal.new("800.00"))
      assert Decimal.equal?(invoice.gross_amount, Decimal.new("864.00"))
    end

    test "returns error for invalid XML" do
      assert {:error, {:invalid_xml, _}} = Parser.parse("<not-valid>")
    end

    test "returns error for empty string" do
      assert {:error, {:invalid_xml, _}} = Parser.parse("")
    end

    test "returns nil purchase_order when absent" do
      xml = File.read!(Path.join(@fixtures_path, "sample_income.xml"))

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.purchase_order == nil
    end

    test "extracts AU_CON purchase_order from NrZamowienia with PO prefix" do
      xml = File.read!(Path.join(@fixtures_path, "sample_income_with_po.xml"))

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.purchase_order == "AU_CON_NW9BBJ4VJ"
    end

    test "extracts AU_CON purchase_order from DodatkowyOpis value" do
      xml = File.read!(Path.join(@fixtures_path, "sample_expense_with_dodatkowy_opis_po.xml"))

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.purchase_order == "AU_CON_X7KLM2P9Q"
    end

    test "NrZamowienia takes precedence over DodatkowyOpis" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
        <Naglowek>
          <KodFormularza kodSystemowy="FA (3)" wersjaSchemy="1-0E">FA</KodFormularza>
          <WariantFormularza>3</WariantFormularza>
          <DataWytworzeniaFa>2025-01-15T10:30:00</DataWytworzeniaFa>
          <SystemInfo>Test</SystemInfo>
        </Naglowek>
        <Podmiot1><DaneIdentyfikacyjne><NIP>1234567890</NIP><Nazwa>Seller</Nazwa></DaneIdentyfikacyjne></Podmiot1>
        <Podmiot2><DaneIdentyfikacyjne><NIP>0987654321</NIP><Nazwa>Buyer</Nazwa></DaneIdentyfikacyjne></Podmiot2>
        <Fa>
          <KodWaluty>PLN</KodWaluty>
          <P_1>2025-01-15</P_1>
          <P_2>FV/2025/001</P_2>
          <NrZamowienia>PO: AU_CON_AAABBB111</NrZamowienia>
          <DodatkowyOpis>
            <Klucz>Numer zamowienia</Klucz>
            <Wartosc>AU_CON_CCCDDDEEE</Wartosc>
          </DodatkowyOpis>
          <P_13_1>1000.00</P_13_1>
          <P_15>1230.00</P_15>
          <Adnotacje><P_16>2</P_16><P_17>2</P_17><P_18>2</P_18><P_18A>2</P_18A><Zwolnienie><P_19N>1</P_19N></Zwolnienie><NoweSrodkiTransportu><P_22N>1</P_22N></NoweSrodkiTransportu><P_23>2</P_23><PMarzy><P_PMarzyN>1</P_PMarzyN></PMarzy></Adnotacje>
          <FaWiersz><NrWierszaFa>1</NrWierszaFa><P_7>Item</P_7><P_11>1000.00</P_11><P_12>23</P_12></FaWiersz>
        </Fa>
      </Faktura>
      """

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.purchase_order == "AU_CON_AAABBB111"
    end

    test "extracts AU_CON from DodatkowyOpis key field" do
      xml = dodatkowy_opis_xml("AU_CON_R4TYU8P2L", "some value")

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.purchase_order == "AU_CON_R4TYU8P2L"
    end

    test "extracts AU_CON from DodatkowyOpis value with PO prefix" do
      xml = dodatkowy_opis_xml("Uwagi", "PO: AU_CON_H5JKL9M3N")

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.purchase_order == "AU_CON_H5JKL9M3N"
    end

    test "extracts AU_CON from DodatkowyOpis value without prefix" do
      xml = dodatkowy_opis_xml("Notes", "AU_CON_W2XYZ6Q8V")

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.purchase_order == "AU_CON_W2XYZ6Q8V"
    end

    test "uppercases lowercase AU_CON code" do
      xml = dodatkowy_opis_xml("Notes", "au_con_nw9bbj4vj")

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.purchase_order == "AU_CON_NW9BBJ4VJ"
    end

    test "ignores non-AU_CON purchase orders" do
      xml = dodatkowy_opis_xml("Purchase Order", "PO-2025-100")

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.purchase_order == nil
    end

    test "returns nil when DodatkowyOpis has unrelated content" do
      xml = dodatkowy_opis_xml("Termin platnosci", "30 dni")

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.purchase_order == nil
    end

    test "returns nil when NrZamowienia has non-AU_CON value" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
        <Naglowek>
          <KodFormularza kodSystemowy="FA (3)" wersjaSchemy="1-0E">FA</KodFormularza>
          <WariantFormularza>3</WariantFormularza>
          <DataWytworzeniaFa>2025-01-15T10:30:00</DataWytworzeniaFa>
          <SystemInfo>Test</SystemInfo>
        </Naglowek>
        <Podmiot1><DaneIdentyfikacyjne><NIP>1234567890</NIP><Nazwa>Seller</Nazwa></DaneIdentyfikacyjne></Podmiot1>
        <Podmiot2><DaneIdentyfikacyjne><NIP>0987654321</NIP><Nazwa>Buyer</Nazwa></DaneIdentyfikacyjne></Podmiot2>
        <Fa>
          <KodWaluty>PLN</KodWaluty>
          <P_1>2025-01-15</P_1>
          <P_2>FV/2025/001</P_2>
          <NrZamowienia>ZAM/2025/001</NrZamowienia>
          <P_13_1>1000.00</P_13_1>
          <P_15>1230.00</P_15>
          <Adnotacje><P_16>2</P_16><P_17>2</P_17><P_18>2</P_18><P_18A>2</P_18A><Zwolnienie><P_19N>1</P_19N></Zwolnienie><NoweSrodkiTransportu><P_22N>1</P_22N></NoweSrodkiTransportu><P_23>2</P_23><PMarzy><P_PMarzyN>1</P_PMarzyN></PMarzy></Adnotacje>
          <FaWiersz><NrWierszaFa>1</NrWierszaFa><P_7>Item</P_7><P_11>1000.00</P_11><P_12>23</P_12></FaWiersz>
        </Fa>
      </Faktura>
      """

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.purchase_order == nil
    end

    test "extracts seller and buyer addresses from Adres elements" do
      xml = File.read!(Path.join(@fixtures_path, "sample_income.xml"))

      assert {:ok, invoice} = Parser.parse(xml)

      assert invoice.seller_address == %{
               street: "ul. Testowa 1",
               city: "Warszawa",
               postal_code: "00-001",
               country: "PL"
             }

      assert invoice.buyer_address == %{
               street: "ul. Kupna 5",
               city: "Kraków",
               postal_code: "00-002",
               country: "PL"
             }
    end

    test "parses address when everything is in AdresL1 (no AdresL2)" do
      xml = File.read!(Path.join(@fixtures_path, "sample_address_in_l1_only.xml"))

      assert {:ok, invoice} = Parser.parse(xml)

      assert invoice.seller_address == %{
               street: "Św. Mikołaja 8-11",
               city: "Wrocław",
               postal_code: "50-125",
               country: "PL"
             }

      assert invoice.buyer_address == %{
               street: "ul. Droga Dębińska 3A/3",
               city: "Poznań",
               postal_code: "61-555",
               country: "PL"
             }
    end

    test "keeps street as-is when AdresL1 has no postal code pattern" do
      xml = File.read!(Path.join(@fixtures_path, "sample_foreign_address.xml"))

      assert {:ok, invoice} = Parser.parse(xml)

      # Foreign address: no postal code pattern, street kept as-is
      assert invoice.seller_address == %{
               street: "Friedrichstraße 123",
               city: nil,
               postal_code: nil,
               country: "DE"
             }

      # AdresL2 without postal code: kept as city
      assert invoice.buyer_address == %{
               street: "ul. Testowa 1",
               city: "Warszawa",
               postal_code: nil,
               country: "PL"
             }
    end

    test "returns nil addresses when Adres elements are absent" do
      xml = dodatkowy_opis_xml("Notes", "nothing relevant")

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.seller_address == nil
      assert invoice.buyer_address == nil
    end

    test "extracts sales_date from P_6" do
      xml = File.read!(Path.join(@fixtures_path, "sample_income_with_iban.xml"))

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.sales_date == ~D[2025-01-14]
    end

    test "returns nil sales_date when P_6 is absent" do
      xml = File.read!(Path.join(@fixtures_path, "sample_income.xml"))

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.sales_date == nil
    end

    test "extracts iban from Rachunek/NrRB" do
      xml = File.read!(Path.join(@fixtures_path, "sample_income_with_iban.xml"))

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.iban == "PL61109010140000071219812874"
    end

    test "returns nil iban when Rachunek is absent" do
      xml = File.read!(Path.join(@fixtures_path, "sample_income.xml"))

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.iban == nil
    end
  end

  @spec dodatkowy_opis_xml(String.t(), String.t()) :: String.t()
  defp dodatkowy_opis_xml(key, value) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
      <Naglowek>
        <KodFormularza kodSystemowy="FA (3)" wersjaSchemy="1-0E">FA</KodFormularza>
        <WariantFormularza>3</WariantFormularza>
        <DataWytworzeniaFa>2025-01-15T10:30:00</DataWytworzeniaFa>
        <SystemInfo>Test</SystemInfo>
      </Naglowek>
      <Podmiot1><DaneIdentyfikacyjne><NIP>1234567890</NIP><Nazwa>Seller</Nazwa></DaneIdentyfikacyjne></Podmiot1>
      <Podmiot2><DaneIdentyfikacyjne><NIP>0987654321</NIP><Nazwa>Buyer</Nazwa></DaneIdentyfikacyjne></Podmiot2>
      <Fa>
        <KodWaluty>PLN</KodWaluty>
        <P_1>2025-01-15</P_1>
        <P_2>FV/2025/001</P_2>
        <DodatkowyOpis>
          <Klucz>#{key}</Klucz>
          <Wartosc>#{value}</Wartosc>
        </DodatkowyOpis>
        <P_13_1>1000.00</P_13_1>
        <P_15>1230.00</P_15>
        <Adnotacje><P_16>2</P_16><P_17>2</P_17><P_18>2</P_18><P_18A>2</P_18A><Zwolnienie><P_19N>1</P_19N></Zwolnienie><NoweSrodkiTransportu><P_22N>1</P_22N></NoweSrodkiTransportu><P_23>2</P_23><PMarzy><P_PMarzyN>1</P_PMarzyN></PMarzy></Adnotacje>
        <FaWiersz><NrWierszaFa>1</NrWierszaFa><P_7>Item</P_7><P_11>1000.00</P_11><P_12>23</P_12></FaWiersz>
      </Fa>
    </Faktura>
    """
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
