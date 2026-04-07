defmodule KsefHub.InvoiceExtractor.ContextBuilder do
  @moduledoc """
  Builds domain context strings for the invoice extraction sidecar.

  The context string provides hints to the LLM about the company and expected
  invoice types, improving OCR extraction accuracy.
  """

  alias KsefHub.Companies.Company

  @doc """
  Builds a context string from a company struct.

  The returned string describes the company identity (name, NIP, address) and
  common invoice characteristics (types, currencies) to guide extraction.

  When `type` is provided, adds an explicit hint about which NIP belongs to the
  buyer vs seller — critical for foreign invoices where the AI may confuse the two.

  ## Examples

      iex> company = %KsefHub.Companies.Company{name: "AppUnite S.A.", nip: "5261040828", address: "ul. Piaskowa 3, Poznań"}
      iex> KsefHub.InvoiceExtractor.ContextBuilder.build(company)
      "The company is AppUnite S.A., NIP 5261040828, ul. Piaskowa 3, Poznań. There are two possible invoice types: income (the company sells) and expense (the company buys). This is most likely a Polish VAT invoice (Faktura VAT) or a US invoice. Most common currencies are PLN, USD, EUR, GBP."

      iex> company = %KsefHub.Companies.Company{name: "AppUnite S.A.", nip: "5261040828", address: "ul. Piaskowa 3, Poznań"}
      iex> KsefHub.InvoiceExtractor.ContextBuilder.build(company, :expense)
      "The company is AppUnite S.A., NIP 5261040828, ul. Piaskowa 3, Poznań. This is an expense (cost) invoice — the company is the buyer. The company's NIP is 5261040828, so if you're unsure which NIP is the buyer's, it's likely 5261040828. This is most likely a Polish VAT invoice (Faktura VAT) or a US invoice. Most common currencies are PLN, USD, EUR, GBP."
  """
  @spec build(Company.t(), atom() | nil) :: String.t()
  def build(%Company{} = company, type \\ nil) do
    [
      company_clause(company),
      type_hint(company.nip, type),
      "This is most likely a Polish VAT invoice (Faktura VAT) or a US invoice.",
      "Most common currencies are PLN, USD, EUR, GBP."
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  @spec company_clause(Company.t()) :: String.t()
  defp company_clause(%Company{name: name, nip: nip, address: address})
       when is_binary(address) and address != "" do
    "The company is #{name}, NIP #{nip}, #{address}."
  end

  defp company_clause(%Company{name: name, nip: nip}) do
    "The company is #{name}, NIP #{nip}."
  end

  @spec type_hint(String.t() | nil, atom() | nil) :: String.t() | nil
  defp type_hint(nip, type) when type in [:expense, "expense"] and is_binary(nip) do
    "This is an expense (cost) invoice — the company is the buyer. " <>
      "The company's NIP is #{nip}, so if you're unsure which NIP is the buyer's, it's likely #{nip}."
  end

  defp type_hint(nip, type) when type in [:income, "income"] and is_binary(nip) do
    "This is an income (sales) invoice — the company is the seller. " <>
      "The company's NIP is #{nip}, so if you're unsure which NIP is the seller's, it's likely #{nip}."
  end

  defp type_hint(_nip, _type) do
    "There are two possible invoice types: income (the company sells) and expense (the company buys)."
  end
end
