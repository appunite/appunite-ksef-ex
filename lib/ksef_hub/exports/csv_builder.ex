defmodule KsefHub.Exports.CsvBuilder do
  @moduledoc "Builds CSV binary from a list of invoices. Pure function, no side effects."

  alias KsefHub.Invoices.Invoice

  @headers [
    "Invoice Number",
    "Issue Date",
    "Type",
    "Source",
    "Seller NIP",
    "Seller Name",
    "Buyer NIP",
    "Buyer Name",
    "Net Amount",
    "VAT Amount",
    "Gross Amount",
    "Currency",
    "Category",
    "Tags",
    "KSeF Number",
    "Added At",
    "Original Filename",
    "Duplicate Status"
  ]

  @doc "Builds a CSV binary (UTF-8 with BOM) from a list of invoices."
  @spec build([Invoice.t()]) :: binary()
  def build(invoices) do
    rows = Enum.map(invoices, &invoice_to_row/1)

    csv =
      [@headers | rows]
      |> Enum.map_join("\r\n", &encode_row/1)

    <<0xEF, 0xBB, 0xBF>> <> csv <> "\r\n"
  end

  @spec invoice_to_row(Invoice.t()) :: [String.t()]
  defp invoice_to_row(invoice) do
    [
      s(invoice.invoice_number),
      format_date(invoice.issue_date),
      s(invoice.type),
      s(invoice.source),
      s(invoice.seller_nip),
      s(invoice.seller_name),
      s(invoice.buyer_nip),
      s(invoice.buyer_name),
      format_decimal(invoice.net_amount),
      format_decimal(invoice.vat_amount),
      format_decimal(invoice.gross_amount),
      s(invoice.currency),
      format_category(invoice),
      format_tags(invoice),
      s(invoice.ksef_number),
      format_datetime(invoice.inserted_at),
      s(invoice.original_filename),
      s(invoice.duplicate_status)
    ]
  end

  @spec s(term()) :: String.t()
  defp s(nil), do: ""
  defp s(value), do: to_string(value)

  @spec encode_row([String.t()]) :: String.t()
  defp encode_row(fields) do
    Enum.map_join(fields, ",", &escape_field/1)
  end

  @spec escape_field(String.t()) :: String.t()
  defp escape_field(value) do
    value = sanitize_formula(value)

    if needs_quoting?(value) do
      ~s("#{String.replace(value, ~s("), ~s(""))}")
    else
      value
    end
  end

  @spec sanitize_formula(String.t()) :: String.t()
  defp sanitize_formula(<<c, _::binary>> = value) when c in [?=, ?+, ?-, ?@] do
    "'" <> value
  end

  defp sanitize_formula(value), do: value

  @spec needs_quoting?(String.t()) :: boolean()
  defp needs_quoting?(value) do
    String.contains?(value, [",", "\"", "\n", "\r"])
  end

  @spec format_date(Date.t() | nil) :: String.t()
  defp format_date(nil), do: ""
  defp format_date(%Date{} = date), do: Date.to_iso8601(date)

  @spec format_decimal(Decimal.t() | nil) :: String.t()
  defp format_decimal(nil), do: ""
  defp format_decimal(%Decimal{} = d), do: Decimal.to_string(d)

  @spec format_datetime(NaiveDateTime.t() | DateTime.t() | nil) :: String.t()
  defp format_datetime(nil), do: ""
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  @spec format_category(Invoice.t()) :: String.t()
  defp format_category(%{category: %{name: name}}) when is_binary(name), do: name
  defp format_category(_), do: ""

  @spec format_tags(Invoice.t()) :: String.t()
  defp format_tags(%{tags: tags}) when is_list(tags) do
    Enum.map_join(tags, "; ", & &1.name)
  end

  defp format_tags(_), do: ""
end
