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

  ## Examples

      iex> company = %KsefHub.Companies.Company{name: "AppUnite S.A.", nip: "5261040828", address: "ul. Piaskowa 3, Poznań"}
      iex> KsefHub.InvoiceExtractor.ContextBuilder.build(company)
      "There are two possible invoice types: income (the company sells) and expense (the company buys). The company is AppUnite S.A., NIP 5261040828, ul. Piaskowa 3, Poznań. This is most likely a Polish VAT invoice (Faktura VAT) or a US invoice. Most common currencies are PLN, USD, EUR, GBP."
  """
  @spec build(Company.t()) :: String.t()
  def build(%Company{} = company) do
    [
      "There are two possible invoice types: income (the company sells) and expense (the company buys).",
      company_clause(company),
      "This is most likely a Polish VAT invoice (Faktura VAT) or a US invoice.",
      "Most common currencies are PLN, USD, EUR, GBP."
    ]
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
end
