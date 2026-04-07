defmodule KsefHub.Invoices.NipVerifier do
  @moduledoc """
  Verifies that extracted invoice NIPs match the owning company.

  Used by both PDF upload (manual) and email inbound flows to reject
  invoices that don't belong to the company.
  """

  alias KsefHub.InvoiceExtractor.Placeholders
  alias KsefHub.Nip

  require Logger

  @type verify_result ::
          :ok
          | {:error, :buyer_nip_mismatch}
          | {:error, :seller_nip_mismatch}
          | {:error, :unknown_invoice_type}

  @type expense_result ::
          {:ok, :expense}
          | {:error, :income_not_allowed}
          | {:error, :nip_mismatch}
          | {:undetermined, :needs_review}

  @doc """
  Verifies the extracted NIP matches the company for the given invoice type.

  For expenses, checks buyer NIP. For income, checks seller NIP.
  Returns `:ok` when the NIP matches or couldn't be extracted (fallback to company fields).
  """
  @spec verify_for_type(map(), String.t() | nil, atom()) :: verify_result()
  def verify_for_type(_extracted, nil, _type), do: :ok

  def verify_for_type(extracted, company_nip, type) do
    case type_to_nip_key(type) do
      {:ok, nip_key, mismatch_error} ->
        raw_nip = get_nip(extracted, nip_key)
        extracted_nip = Nip.normalize(raw_nip)
        normalized_company = Nip.normalize(company_nip)

        cond do
          not present?(extracted_nip) ->
            :ok

          extracted_nip == normalized_company ->
            :ok

          true ->
            Logger.warning(
              "NIP mismatch on #{type}: extracted #{mask_nip(raw_nip)} " <>
                "(normalized: #{mask_nip(extracted_nip)}) != company #{mask_nip(normalized_company)}"
            )

            {:error, mismatch_error}
        end

      :error ->
        {:error, :unknown_invoice_type}
    end
  end

  @spec type_to_nip_key(atom() | String.t()) :: {:ok, atom(), atom()} | :error
  defp type_to_nip_key(t) when t in [:expense, "expense"],
    do: {:ok, :buyer_nip, :buyer_nip_mismatch}

  defp type_to_nip_key(t) when t in [:income, "income"],
    do: {:ok, :seller_nip, :seller_nip_mismatch}

  defp type_to_nip_key(_), do: :error

  @doc """
  Verifies that the extracted invoice is an expense for the company.

  More detailed than `verify_for_type/3` — distinguishes income invoices
  from true mismatches. Used by the email inbound flow.

  Returns:
    - `{:ok, :expense}` — buyer NIP matches company NIP
    - `{:error, :income_not_allowed}` — seller NIP matches (this is an income invoice)
    - `{:error, :nip_mismatch}` — neither NIP matches
    - `{:undetermined, :needs_review}` — buyer NIP could not be extracted
  """
  @spec verify_expense(map(), String.t()) :: expense_result()
  def verify_expense(extracted, company_nip) do
    buyer_nip = get_nip(extracted, :buyer_nip) |> Nip.normalize()
    seller_nip = get_nip(extracted, :seller_nip) |> Nip.normalize()
    normalized_company = Nip.normalize(company_nip)

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

  @spec mask_nip(String.t() | nil) :: String.t()
  defp mask_nip(nil), do: "nil"
  defp mask_nip(""), do: "\"\""

  defp mask_nip(value) when is_binary(value) do
    digits = String.replace(value, ~r/[^0-9]/, "")

    case String.length(digits) do
      len when len >= 6 -> String.slice(digits, 0, 3) <> "***" <> String.slice(digits, -3, 3)
      _ -> "***"
    end
  end

  @spec present?(term()) :: boolean()
  defp present?(nil), do: false
  defp present?(""), do: false

  defp present?(value) when is_binary(value) do
    trimmed = String.trim(value)
    trimmed != "" and not Placeholders.placeholder?(trimmed)
  end

  defp present?(_), do: false
end
