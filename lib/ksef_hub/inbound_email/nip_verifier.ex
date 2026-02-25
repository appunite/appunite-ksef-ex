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
    buyer_nip = get_nip(extracted, :buyer_nip)
    seller_nip = get_nip(extracted, :seller_nip)

    cond do
      present?(buyer_nip) && buyer_nip == company_nip -> {:ok, :expense}
      present?(seller_nip) && seller_nip == company_nip -> {:error, :income_not_allowed}
      present?(buyer_nip) -> {:error, :nip_mismatch}
      true -> {:undetermined, :needs_review}
    end
  end

  @spec get_nip(map(), atom()) :: String.t() | nil
  defp get_nip(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  @spec present?(term()) :: boolean()
  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true
end
