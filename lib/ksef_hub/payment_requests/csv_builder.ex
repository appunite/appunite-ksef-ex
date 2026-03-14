defmodule KsefHub.PaymentRequests.CsvBuilder do
  @moduledoc "Builds Polish bank CSV from a list of payment requests. Pure function, no side effects."

  alias KsefHub.PaymentRequests.PaymentRequest

  @headers [
    "Nazwa odbiorcy",
    "Adres odbiorcy",
    "Nr rachunku (IBAN)",
    "Kwota",
    "Waluta",
    "Tytul"
  ]

  @doc "Builds a CSV binary (UTF-8 with BOM, CRLF line endings) from payment requests."
  @spec build([PaymentRequest.t()]) :: binary()
  def build(payment_requests) do
    rows = Enum.map(payment_requests, &payment_request_to_row/1)

    csv =
      [@headers | rows]
      |> Enum.map_join("\r\n", &encode_row/1)

    <<0xEF, 0xBB, 0xBF>> <> csv <> "\r\n"
  end

  @spec payment_request_to_row(PaymentRequest.t()) :: [String.t()]
  defp payment_request_to_row(pr) do
    [
      s(pr.recipient_name),
      PaymentRequest.format_address(pr.recipient_address),
      s(pr.iban),
      format_decimal(pr.amount),
      s(pr.currency),
      s(pr.title)
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
  defp sanitize_formula(value) do
    if Regex.match?(~r/^\s*[=+\-@]/, value) do
      "'" <> value
    else
      value
    end
  end

  @spec needs_quoting?(String.t()) :: boolean()
  defp needs_quoting?(value) do
    String.contains?(value, [",", "\"", "\n", "\r"])
  end

  @spec format_decimal(Decimal.t() | nil) :: String.t()
  defp format_decimal(nil), do: ""
  defp format_decimal(%Decimal{} = d), do: Decimal.to_string(d)
end
