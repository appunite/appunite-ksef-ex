defmodule KsefHub.Invoices.KsefNumber do
  @moduledoc """
  Validates KSeF invoice number format.

  Official format: `9999999999-RRRRMMDD-FFFFFFFFFFFF-FF`
  - 10-digit seller NIP
  - 8-digit date of submission to KSeF (YYYYMMDD)
  - 12-character auto-generated technical part (uppercase hex)
  - 2-character auto-calculated checksum (uppercase hex)

  Reference: https://ksef.podatki.gov.pl/informacje-ogolne-ksef-20/numer-ksef-i-zbiorczy-identyfikator/

  Used to filter out garbage values (e.g. QR code URL path segments)
  that the invoice extractor sidecar sometimes returns as ksef_number.
  """

  @ksef_format ~r/^\d{10}-\d{8}-[0-9A-F]{12}-[0-9A-F]{2}$/

  @doc """
  Returns the ksef_number if it matches the official format, `nil` otherwise.

  ## Examples

      iex> KsefHub.Invoices.KsefNumber.validate("5555555555-20250828-010080615740-E4")
      "5555555555-20250828-010080615740-E4"

      iex> KsefHub.Invoices.KsefNumber.validate("8992736090/09-04-2026/U-J8M5W6XHhnxCnk")
      nil

      iex> KsefHub.Invoices.KsefNumber.validate(nil)
      nil
  """
  @spec validate(String.t() | nil) :: String.t() | nil
  def validate(nil), do: nil

  def validate(value) when is_binary(value) do
    if Regex.match?(@ksef_format, value) and valid_date?(value), do: value, else: nil
  end

  @doc """
  Validates the ksef_number format and cross-checks that the NIP prefix
  matches the given seller_nip. Returns `nil` if either check fails.

  When `seller_nip` is `nil` (not extracted), falls back to format-only validation.

  ## Examples

      iex> KsefHub.Invoices.KsefNumber.validate("5555555555-20250828-010080615740-E4", "5555555555")
      "5555555555-20250828-010080615740-E4"

      iex> KsefHub.Invoices.KsefNumber.validate("5555555555-20250828-010080615740-E4", "9999999999")
      nil

      iex> KsefHub.Invoices.KsefNumber.validate("5555555555-20250828-010080615740-E4", nil)
      "5555555555-20250828-010080615740-E4"
  """
  @spec validate(String.t() | nil, String.t() | nil) :: String.t() | nil
  def validate(value, nil), do: validate(value)
  def validate(nil, _seller_nip), do: nil

  def validate(value, seller_nip) when is_binary(value) and is_binary(seller_nip) do
    case validate(value) do
      nil ->
        nil

      valid ->
        nip_prefix = String.slice(valid, 0, 10)
        if nip_prefix == seller_nip, do: valid, else: nil
    end
  end

  # Extracts the YYYYMMDD segment and validates it as a real calendar date.
  @spec valid_date?(String.t()) :: boolean()
  defp valid_date?(value) do
    <<_nip::binary-size(11), date::binary-size(8), _rest::binary>> = value

    case Date.from_iso8601(
           <<String.slice(date, 0, 4)::binary, "-", String.slice(date, 4, 2)::binary, "-",
             String.slice(date, 6, 2)::binary>>
         ) do
      {:ok, _} -> true
      _ -> false
    end
  end
end
