defmodule KsefHub.Exports.CsvBuilder do
  @moduledoc "Builds CSV binary from a list of invoices. Pure function, no side effects."

  alias KsefHub.Invoices.Invoice

  @standard_headers [
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

  @extended_headers [
    "Invoice ID",
    "Company ID",
    "Cost Line",
    "Project Tag",
    "Is Excluded",
    "Access Restricted",
    "Payment Status",
    "Payment Date",
    "Category Identifier",
    "Prediction Status",
    "Predicted Category",
    "Predicted Tag",
    "Category Confidence %",
    "Tag Confidence %",
    "Extraction Status"
  ]

  @doc "Builds a CSV binary (UTF-8 with BOM) from a list of invoices."
  @spec build([Invoice.t()], keyword()) :: binary()
  def build(invoices, opts \\ []) do
    extended = Keyword.get(opts, :extended, false)
    headers = if extended, do: @standard_headers ++ @extended_headers, else: @standard_headers
    rows = Enum.map(invoices, &invoice_to_row(&1, extended))

    csv =
      [headers | rows]
      |> Enum.map_join("\r\n", &encode_row/1)

    <<0xEF, 0xBB, 0xBF>> <> csv <> "\r\n"
  end

  @spec invoice_to_row(Invoice.t(), boolean()) :: [String.t()]
  defp invoice_to_row(invoice, extended) do
    standard = [
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

    if extended do
      standard ++ extended_fields(invoice)
    else
      standard
    end
  end

  @spec extended_fields(Invoice.t()) :: [String.t()]
  defp extended_fields(invoice) do
    {payment_status, payment_date} = extract_payment_info(invoice)

    [
      s(invoice.id),
      s(invoice.company_id),
      s(invoice.expense_cost_line),
      s(invoice.project_tag),
      format_boolean(invoice.is_excluded),
      format_boolean(invoice.access_restricted),
      payment_status,
      payment_date,
      format_category_identifier(invoice),
      s(invoice.prediction_status),
      s(invoice.prediction_expense_category_name),
      s(invoice.prediction_expense_tag_name),
      format_confidence(invoice.prediction_expense_category_confidence),
      format_confidence(invoice.prediction_expense_tag_confidence),
      s(invoice.extraction_status)
    ]
  end

  @spec extract_payment_info(Invoice.t()) :: {String.t(), String.t()}
  defp extract_payment_info(%{payment_requests: prs}) when is_list(prs) do
    case Enum.find(prs, &(&1.status == :paid)) do
      %{status: status, paid_at: paid_at} ->
        {s(status), format_datetime(paid_at)}

      nil ->
        case List.first(prs) do
          nil -> {"", ""}
          %{status: status} -> {s(status), ""}
        end
    end
  end

  defp extract_payment_info(_), do: {"", ""}

  @spec format_category_identifier(Invoice.t()) :: String.t()
  defp format_category_identifier(%{category: %{identifier: id}}) when is_binary(id), do: id
  defp format_category_identifier(_), do: ""

  @spec format_boolean(boolean() | nil) :: String.t()
  defp format_boolean(true), do: "true"
  defp format_boolean(false), do: "false"
  defp format_boolean(nil), do: ""

  @spec format_confidence(float() | nil) :: String.t()
  defp format_confidence(nil), do: ""

  defp format_confidence(value) when is_float(value) do
    value
    |> Kernel.*(100)
    |> Float.round(1)
    |> Float.to_string()
  end

  # --- Shared formatting helpers ---

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
