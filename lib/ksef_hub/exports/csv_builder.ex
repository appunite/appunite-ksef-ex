defmodule KsefHub.Exports.CsvBuilder do
  @moduledoc "Builds CSV binary from a list of invoices. Pure function, no side effects."

  alias KsefHub.Invoices.Invoice

  @headers [
    "Invoice Number",
    "Issue Date",
    "Sales Date",
    "Due Date",
    "Billing Period",
    "Type",
    "Status",
    "Source",
    "Seller NIP",
    "Seller Name",
    "Seller Address",
    "Buyer NIP",
    "Buyer Name",
    "Buyer Address",
    "Net Amount",
    "Gross Amount",
    "Currency",
    "IBAN",
    "Purchase Order",
    "Category",
    "Tags",
    "Note",
    "KSeF Number",
    "Added At",
    "Added By",
    "Updated At",
    "Original Filename",
    "Duplicate Status",
    "Invoice Kind",
    "Corrected Invoice Number",
    "Corrected Invoice KSeF Number",
    "Correction Reason"
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
      format_date(invoice.sales_date),
      format_date(invoice.due_date),
      format_billing_period(invoice.billing_date_from, invoice.billing_date_to),
      s(invoice.type),
      s(invoice.expense_approval_status),
      s(invoice.source),
      s(invoice.seller_nip),
      s(invoice.seller_name),
      format_address(invoice.seller_address),
      s(invoice.buyer_nip),
      s(invoice.buyer_name),
      format_address(invoice.buyer_address),
      format_decimal(invoice.net_amount),
      format_decimal(invoice.gross_amount),
      s(invoice.currency),
      s(invoice.iban),
      s(invoice.purchase_order),
      format_category(invoice),
      format_tags(invoice),
      s(invoice.note),
      s(invoice.ksef_number),
      format_datetime(invoice.inserted_at),
      Invoice.added_by_label(invoice),
      format_datetime(invoice.updated_at),
      s(invoice.original_filename),
      s(invoice.duplicate_status),
      s(invoice.invoice_kind),
      s(invoice.corrected_invoice_number),
      s(invoice.corrected_invoice_ksef_number),
      s(invoice.correction_reason)
    ]
  end

  @spec s(term()) :: String.t()
  defp s(nil), do: ""
  defp s(value), do: to_string(value)

  @spec encode_row([String.t()]) :: String.t()
  defp encode_row(fields) do
    Enum.map_join(fields, ";", &escape_field/1)
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
  defp sanitize_formula(value) do
    if Regex.match?(~r/^\s*[=+\-@]/, value) do
      "'" <> value
    else
      value
    end
  end

  @spec needs_quoting?(String.t()) :: boolean()
  defp needs_quoting?(value) do
    String.contains?(value, [";", "\"", "\n", "\r"])
  end

  @spec format_date(Date.t() | nil) :: String.t()
  defp format_date(nil), do: ""
  defp format_date(%Date{} = date), do: Date.to_iso8601(date)

  @spec format_billing_period(Date.t() | nil, Date.t() | nil) :: String.t()
  defp format_billing_period(nil, _), do: ""
  defp format_billing_period(_, nil), do: ""

  defp format_billing_period(%Date{} = from, %Date{} = to) do
    if Date.compare(from, to) == :eq do
      Calendar.strftime(from, "%Y-%m")
    else
      "#{Calendar.strftime(from, "%Y-%m")} – #{Calendar.strftime(to, "%Y-%m")}"
    end
  end

  @spec format_decimal(Decimal.t() | nil) :: String.t()
  defp format_decimal(nil), do: ""
  defp format_decimal(%Decimal{} = d), do: Decimal.to_string(d)

  @spec format_datetime(NaiveDateTime.t() | DateTime.t() | nil) :: String.t()
  defp format_datetime(nil), do: ""
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  @spec format_category(Invoice.t()) :: String.t()
  defp format_category(%{category: %{name: name}}) when is_binary(name), do: name
  defp format_category(%{category: %{identifier: id}}) when is_binary(id), do: id
  defp format_category(_), do: ""

  @spec format_address(map() | nil) :: String.t()
  defp format_address(addr), do: Invoice.format_address(addr)

  @spec format_tags(Invoice.t()) :: String.t()
  defp format_tags(%{tags: tags}) when is_list(tags) do
    Enum.join(tags, ", ")
  end

  defp format_tags(_), do: ""
end
