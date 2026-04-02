defmodule KsefHub.Invoices.PurchaseOrder do
  @moduledoc """
  Extracts and normalizes AppUnite purchase order codes.

  Matches the pattern `AU_CON_XXXXXXXXX` where `XXXXXXXXX` is exactly 9
  alphanumeric characters. Handles optional `PO:` prefix and case variations.
  """

  @au_po_regex ~r/AU_CON_[A-Z0-9]{9}\b/i

  @doc """
  Extracts an AppUnite purchase order code from text.

  Looks for the `AU_CON_XXXXXXXXX` pattern anywhere in the input, ignoring
  case and optional prefixes like `PO:`. Returns the uppercased code or `nil`.

  ## Examples

      iex> KsefHub.Invoices.PurchaseOrder.extract("PO: AU_CON_NW9BBJ4VJ")
      "AU_CON_NW9BBJ4VJ"

      iex> KsefHub.Invoices.PurchaseOrder.extract("au_con_nw9bbj4vj")
      "AU_CON_NW9BBJ4VJ"

      iex> KsefHub.Invoices.PurchaseOrder.extract("PO-2025-001")
      nil

      iex> KsefHub.Invoices.PurchaseOrder.extract("")
      nil
  """
  @spec extract(String.t()) :: String.t() | nil
  def extract(text) when is_binary(text) do
    case Regex.run(@au_po_regex, text) do
      [match] -> String.upcase(match)
      _ -> nil
    end
  end

  def extract(_), do: nil
end
