defmodule KsefHub.Invoices.Parser do
  @moduledoc """
  Parses FA(3) XML invoices from KSeF into structured maps.
  Uses SweetXml for XPath-based extraction.
  """

  import SweetXml

  @doc """
  Parses an FA(3) XML string into a structured invoice map.
  Returns `{:ok, map}` or `{:error, reason}`.
  """
  def parse(xml_string) when is_binary(xml_string) do
    doc = SweetXml.parse(xml_string, namespace_conformant: true, quiet: true)

    {:ok,
     %{
       invoice_number: xpath(doc, ~x"//P_2/text()"s),
       issue_date: xpath(doc, ~x"//P_1/text()"s) |> parse_date(),
       seller_nip: xpath(doc, ~x"//Podmiot1//NIP/text()"s),
       seller_name: extract_name(doc, "Podmiot1"),
       buyer_nip: xpath(doc, ~x"//Podmiot2//NIP/text()"s),
       buyer_name: extract_name(doc, "Podmiot2"),
       net_amount: xpath(doc, ~x"//P_13_1/text()"s) |> parse_decimal(),
       vat_amount: xpath(doc, ~x"//P_14_1/text()"s) |> parse_decimal(),
       gross_amount: xpath(doc, ~x"//P_15/text()"s) |> parse_decimal(),
       currency: xpath(doc, ~x"//KodWaluty/text()"s) |> default_currency(),
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
  def determine_type(parsed_invoice, our_nip) do
    cond do
      parsed_invoice.seller_nip == our_nip -> "income"
      parsed_invoice.buyer_nip == our_nip -> "expense"
      true -> "income"
    end
  end

  # --- Private ---

  defp extract_name(doc, subject) do
    # Try Nazwa first (company), then personal name fields
    name = xpath(doc, ~x"//#{subject}//Nazwa/text()"s)

    if name != "" do
      name
    else
      first = xpath(doc, ~x"//#{subject}//ImiePierwsze/text()"s)
      last = xpath(doc, ~x"//#{subject}//Nazwisko/text()"s)
      String.trim("#{first} #{last}")
    end
  end

  defp parse_line_items(doc) do
    doc
    |> xpath(~x"//FaWiersz"l)
    |> Enum.map(fn item ->
      %{
        line_number: xpath(item, ~x"./NrWierszaFa/text()"s) |> parse_integer(),
        description: xpath(item, ~x"./P_7/text()"s),
        unit: xpath(item, ~x"./P_8A/text()"s),
        quantity: xpath(item, ~x"./P_8B/text()"s) |> parse_decimal(),
        unit_price: xpath(item, ~x"./P_9A/text()"s) |> parse_decimal(),
        net_amount: xpath(item, ~x"./P_11/text()"s) |> parse_decimal(),
        vat_rate: xpath(item, ~x"./P_12/text()"s) |> parse_decimal()
      }
    end)
  end

  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_decimal(""), do: nil

  defp parse_decimal(str) do
    case Decimal.parse(str) do
      {decimal, ""} -> decimal
      {decimal, _rest} -> decimal
      :error -> nil
    end
  end

  defp parse_integer(""), do: nil

  defp parse_integer(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp default_currency(""), do: "PLN"
  defp default_currency(currency), do: currency
end
