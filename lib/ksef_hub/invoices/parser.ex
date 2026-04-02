defmodule KsefHub.Invoices.Parser do
  @moduledoc """
  Parses FA(3) XML invoices from KSeF into structured maps.
  Uses SweetXml for XPath-based extraction.
  """

  import SweetXml

  # Polish postal code: exactly 2 digits, dash, 3 digits (e.g. "00-001")
  @postal_in_line ~r/^(\d{2}-\d{3})\s+(.+)$/
  @full_address ~r/^(.+?),?\s*(\d{2}-\d{3})\s+([^,]+)/

  @doc """
  Parses an FA(3) XML string into a structured invoice map.
  Returns `{:ok, map}` or `{:error, reason}`.
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, term()}
  def parse(xml_string) when is_binary(xml_string) do
    doc = SweetXml.parse(xml_string, namespace_conformant: true, quiet: true)

    {:ok,
     %{
       invoice_number: xpath(doc, ~x"//*[local-name()='P_2']/text()"s),
       issue_date: xpath(doc, ~x"//*[local-name()='P_1']/text()"s) |> parse_date(),
       sales_date: xpath(doc, ~x"//*[local-name()='P_6']/text()"s) |> parse_date(),
       seller_nip: xpath(doc, ~x"//*[local-name()='Podmiot1']//*[local-name()='NIP']/text()"s),
       seller_name: extract_name(doc, "Podmiot1"),
       buyer_nip: xpath(doc, ~x"//*[local-name()='Podmiot2']//*[local-name()='NIP']/text()"s),
       buyer_name: extract_name(doc, "Podmiot2"),
       # FA(3) net amount summary fields (all optional, sum whichever are present):
       #   P_13_1  — 23% VAT          P_13_6_1 — 0% (domestic, excl. intra-EU & export)
       #   P_13_2  — 8% VAT           P_13_6_2 — 0% intra-EU delivery
       #   P_13_3  — 5% VAT           P_13_6_3 — 0% export
       #   P_13_4  — taxi flat rate    P_13_7   — VAT exempt
       #   P_13_5  — special proc.     P_13_8   — supply outside PL
       #   P_13_9  — EU services       P_13_10  — reverse charge
       #   P_13_11 — margin scheme
       net_amount:
         sum_decimal_fields(
           doc,
           ~w[P_13_1 P_13_2 P_13_3 P_13_4 P_13_5 P_13_6_1 P_13_6_2 P_13_6_3
              P_13_7 P_13_8 P_13_9 P_13_10 P_13_11]
         ),
       gross_amount: xpath(doc, ~x"//*[local-name()='P_15']/text()"s) |> parse_decimal(),
       currency: xpath(doc, ~x"//*[local-name()='KodWaluty']/text()"s) |> default_currency(),
       purchase_order: extract_purchase_order(doc),
       iban: extract_iban(doc),
       seller_address: extract_address(doc, "Podmiot1"),
       buyer_address: extract_address(doc, "Podmiot2"),
       line_items: parse_line_items(doc)
     }}
  rescue
    e ->
      {:error, {:invalid_xml, Exception.message(e)}}
  catch
    :exit, reason ->
      {:error, {:invalid_xml, inspect(reason)}}
  end

  @doc """
  Determines invoice type (income/expense) based on our NIP.
  If our NIP matches Podmiot1 (seller), it's income. If Podmiot2 (buyer), expense.
  """
  @spec determine_type(map(), String.t()) :: :income | :expense
  def determine_type(parsed_invoice, our_nip) do
    cond do
      parsed_invoice.seller_nip == our_nip -> :income
      parsed_invoice.buyer_nip == our_nip -> :expense
      true -> :income
    end
  end

  # --- Private ---

  @spec extract_iban(term()) :: String.t() | nil
  defp extract_iban(doc) do
    presence(
      xpath(
        doc,
        ~x"//*[local-name()='Fa']//*[local-name()='Rachunek']//*[local-name()='NrRB']/text()"s
      )
    ) ||
      presence(xpath(doc, ~x"//*[local-name()='Podmiot1']//*[local-name()='NrRB']/text()"s))
  end

  @spec presence(String.t()) :: String.t() | nil
  defp presence(""), do: nil
  defp presence(value), do: value

  @spec extract_address(term(), String.t()) :: map() | nil
  defp extract_address(doc, subject) do
    country =
      xpath(
        doc,
        ~x"//*[local-name()='#{subject}']//*[local-name()='Adres']//*[local-name()='KodKraju']/text()"s
      )

    addr_l1 =
      xpath(
        doc,
        ~x"//*[local-name()='#{subject}']//*[local-name()='Adres']//*[local-name()='AdresL1']/text()"s
      )

    addr_l2 =
      xpath(
        doc,
        ~x"//*[local-name()='#{subject}']//*[local-name()='Adres']//*[local-name()='AdresL2']/text()"s
      )

    {street, city, postal_code} = parse_address_fields(addr_l1, addr_l2)

    addr = %{
      street: presence(street),
      city: presence(city),
      postal_code: presence(postal_code),
      country: presence(country)
    }

    if Enum.all?(Map.values(addr), &is_nil/1), do: nil, else: addr
  end

  @spec parse_address_fields(String.t(), String.t()) ::
          {String.t() | nil, String.t() | nil, String.t() | nil}
  defp parse_address_fields(raw_l1, raw_l2) do
    addr_l1 = String.trim(raw_l1)
    addr_l2 = String.trim(raw_l2)

    if addr_l2 == "" do
      # AdresL2 is empty/blank — try to parse street, postal code, and city from AdresL1
      case Regex.run(@full_address, addr_l1) do
        [_, street, postal_code, city] ->
          {String.trim(street), String.trim(city), postal_code}

        _ ->
          {addr_l1, nil, nil}
      end
    else
      # AdresL2 is present — try to split postal code from city
      case Regex.run(@postal_in_line, addr_l2) do
        [_, postal_code, city] -> {addr_l1, city, postal_code}
        _ -> {addr_l1, addr_l2, nil}
      end
    end
  end

  @spec extract_name(term(), String.t()) :: String.t()
  defp extract_name(doc, subject) do
    # Try Nazwa first (company), then personal name fields
    name = xpath(doc, ~x"//*[local-name()='#{subject}']//*[local-name()='Nazwa']/text()"s)

    if name != "" do
      name
    else
      first =
        xpath(doc, ~x"//*[local-name()='#{subject}']//*[local-name()='ImiePierwsze']/text()"s)

      last =
        xpath(doc, ~x"//*[local-name()='#{subject}']//*[local-name()='Nazwisko']/text()"s)

      String.trim("#{first} #{last}")
    end
  end

  alias KsefHub.Invoices.PurchaseOrder

  @spec extract_purchase_order(term()) :: String.t() | nil
  defp extract_purchase_order(doc) do
    PurchaseOrder.extract(
      xpath(doc, ~x"//*[local-name()='Fa']//*[local-name()='NrZamowienia']/text()"s)
    ) || extract_po_from_dodatkowy_opis(doc)
  end

  @spec extract_po_from_dodatkowy_opis(term()) :: String.t() | nil
  defp extract_po_from_dodatkowy_opis(doc) do
    doc
    |> xpath(~x"//*[local-name()='DodatkowyOpis']"l)
    |> Enum.find_value(fn entry ->
      key = xpath(entry, ~x"./*[local-name()='Klucz']/text()"s)
      value = xpath(entry, ~x"./*[local-name()='Wartosc']/text()"s)

      PurchaseOrder.extract(key) || PurchaseOrder.extract(value)
    end)
  end

  @spec parse_line_items(term()) :: [map()]
  defp parse_line_items(doc) do
    doc
    |> xpath(~x"//*[local-name()='FaWiersz']"l)
    |> Enum.map(fn item ->
      %{
        line_number: xpath(item, ~x"./*[local-name()='NrWierszaFa']/text()"s) |> parse_integer(),
        description: xpath(item, ~x"./*[local-name()='P_7']/text()"s),
        unit: xpath(item, ~x"./*[local-name()='P_8A']/text()"s),
        quantity: xpath(item, ~x"./*[local-name()='P_8B']/text()"s) |> parse_decimal(),
        unit_price: xpath(item, ~x"./*[local-name()='P_9A']/text()"s) |> parse_decimal(),
        net_amount: xpath(item, ~x"./*[local-name()='P_11']/text()"s) |> parse_decimal(),
        vat_rate: xpath(item, ~x"./*[local-name()='P_12']/text()"s) |> parse_decimal()
      }
    end)
  end

  @spec sum_decimal_fields(term(), [String.t()]) :: Decimal.t() | nil
  defp sum_decimal_fields(doc, field_names) do
    field_names
    |> Enum.map(fn name ->
      xpath(doc, ~x"//*[local-name()='#{name}']/text()"s) |> parse_decimal()
    end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      values -> Enum.reduce(values, Decimal.new(0), &Decimal.add/2)
    end
  end

  @spec parse_date(String.t()) :: Date.t() | nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  @spec parse_decimal(String.t()) :: Decimal.t() | nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(str) do
    case Decimal.parse(str) do
      {decimal, ""} -> decimal
      {decimal, _rest} -> decimal
      :error -> nil
    end
  end

  @spec parse_integer(String.t()) :: integer() | nil
  defp parse_integer(""), do: nil

  defp parse_integer(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> nil
    end
  end

  @spec default_currency(String.t()) :: String.t()
  defp default_currency(""), do: "PLN"
  defp default_currency(currency), do: currency
end
