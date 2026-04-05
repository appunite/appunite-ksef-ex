defmodule KsefHub.PaymentRequests.CsvBuilder do
  @moduledoc """
  Builds Polish bank transfer CSV from a list of payment requests.

  Output format matches the standard Polish bank batch import layout:

      kwota,nazwa_kontrahenta,rachunek_kontrahenta,rachunek_zleceniodawcy,szczegóły_płatności,adres_1,adres_2

  - `kwota` — gross amount in grosz (cents), i.e. PLN × 100
  - `rachunek_zleceniodawcy` — orderer (company) IBAN, resolved per currency
  - `szczegóły_płatności` — `/NIP/<nip>/<transfer title>` when NIP is present
  - `adres_1` / `adres_2` — street / postal code + city

  Encoding: UTF-8 with BOM, CRLF line endings (required by Polish bank systems).

  Pure function, no side effects. See ADR 0039 for design rationale.
  """

  alias KsefHub.PaymentRequests.PaymentRequest

  @headers [
    "kwota",
    "nazwa_kontrahenta",
    "rachunek_kontrahenta",
    "rachunek_zleceniodawcy",
    "szczegóły_płatności",
    "adres_1",
    "adres_2"
  ]

  @doc "Builds a CSV binary (UTF-8 with BOM, CRLF line endings) from payment requests and an orderer IBAN."
  @spec build([PaymentRequest.t()], String.t()) :: binary()
  def build(payment_requests, orderer_iban) do
    rows = Enum.map(payment_requests, &payment_request_to_row(&1, orderer_iban))

    csv =
      [@headers | rows]
      |> Enum.map_join("\r\n", &encode_row/1)

    <<0xEF, 0xBB, 0xBF>> <> csv <> "\r\n"
  end

  @spec payment_request_to_row(PaymentRequest.t(), String.t()) :: [String.t()]
  defp payment_request_to_row(pr, orderer_iban) do
    [
      amount_to_cents(pr.amount),
      s(pr.recipient_name),
      s(pr.iban),
      s(orderer_iban),
      format_payment_details(pr.recipient_nip, pr.title),
      address_line_1(pr.recipient_address),
      address_line_2(pr.recipient_address)
    ]
  end

  @spec amount_to_cents(Decimal.t() | nil) :: String.t()
  defp amount_to_cents(nil), do: ""

  defp amount_to_cents(%Decimal{} = d) do
    d |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer() |> Integer.to_string()
  end

  @spec format_payment_details(String.t() | nil, String.t() | nil) :: String.t()
  defp format_payment_details(nil, title), do: s(title)
  defp format_payment_details("", title), do: s(title)
  defp format_payment_details(nip, title), do: "/NIP/#{nip}/#{s(title)}"

  @spec address_line_1(map() | nil) :: String.t()
  defp address_line_1(nil), do: ""
  defp address_line_1(addr), do: s(addr[:street] || addr["street"])

  @spec address_line_2(map() | nil) :: String.t()
  defp address_line_2(nil), do: ""

  defp address_line_2(addr) do
    postal = s(addr[:postal_code] || addr["postal_code"])
    city = s(addr[:city] || addr["city"])

    case {postal, city} do
      {"", ""} -> ""
      {"", c} -> c
      {p, ""} -> p
      {p, c} -> "#{p} #{c}"
    end
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
    value
    |> sanitize_formula()
    |> strip_csv_breakers()
  end

  @spec sanitize_formula(String.t()) :: String.t()
  defp sanitize_formula(value) do
    if Regex.match?(~r/^\s*[=+\-@]/, value) do
      "'" <> value
    else
      value
    end
  end

  @spec strip_csv_breakers(String.t()) :: String.t()
  defp strip_csv_breakers(value) do
    String.replace(value, ~r/[,"\r\n]/, "")
  end
end
