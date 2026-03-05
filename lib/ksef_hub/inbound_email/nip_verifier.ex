defmodule KsefHub.InboundEmail.NipVerifier do
  @moduledoc """
  Verifies that an extracted invoice is an expense for the given company.

  Checks buyer and seller NIPs against the company NIP to determine
  whether the invoice should be accepted, rejected, or flagged for review.
  """

  @type result ::
          {:ok, :expense}
          | {:error, :income_not_allowed}
          | {:error, :nip_mismatch}
          | {:undetermined, :needs_review}

  @doc """
  Verifies that the extracted invoice is an expense for the company.

  Returns:
    - `{:ok, :expense}` — buyer NIP matches company NIP
    - `{:error, :income_not_allowed}` — seller NIP matches (this is an income invoice)
    - `{:error, :nip_mismatch}` — neither NIP matches
    - `{:undetermined, :needs_review}` — buyer NIP could not be extracted
  """
  @spec verify_expense(map(), String.t()) :: result()
  def verify_expense(extracted, company_nip) do
    buyer_nip = get_nip(extracted, :buyer_nip) |> normalize_nip()
    seller_nip = get_nip(extracted, :seller_nip) |> normalize_nip()
    normalized_company = normalize_nip(company_nip)

    cond do
      present?(buyer_nip) && buyer_nip == normalized_company -> {:ok, :expense}
      present?(seller_nip) && seller_nip == normalized_company -> {:error, :income_not_allowed}
      present?(buyer_nip) -> {:error, :nip_mismatch}
      true -> {:undetermined, :needs_review}
    end
  end

  @spec get_nip(map(), atom()) :: String.t() | nil
  defp get_nip(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  # Strips PL prefix, dashes, spaces from Polish NIPs before comparison.
  @spec normalize_nip(String.t() | nil) :: String.t() | nil
  defp normalize_nip(nil), do: nil
  defp normalize_nip(""), do: ""

  defp normalize_nip(value) do
    stripped =
      value
      |> String.trim()
      |> String.replace(~r/^PL/i, "")
      |> String.replace(~r/[\s\-]/, "")

    if Regex.match?(~r/^\d{10}$/, stripped), do: stripped, else: String.trim(value)
  end

  @spec present?(term()) :: boolean()
  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true
end
