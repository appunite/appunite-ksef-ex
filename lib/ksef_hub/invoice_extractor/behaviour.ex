defmodule KsefHub.InvoiceExtractor.Behaviour do
  @moduledoc """
  Behaviour for the invoice extraction sidecar (au-ksef-unstructured).

  Defines callbacks for extracting structured invoice data from PDF files
  and checking the health of the extraction service.
  """

  @doc """
  Extracts structured invoice data from a PDF binary.

  Sends the PDF to the extraction service and returns a string-keyed map
  of extracted fields (e.g., `"seller_nip"`, `"issue_date"`, `"net_amount"`).

  ## Options
    * `:filename` - original filename for the PDF (default: `"invoice.pdf"`)
    * `:context` - domain context string injected into the LLM prompt for better extraction

  ## Returns
    * `{:ok, map()}` - extracted fields as string-keyed map
    * `{:error, :extractor_not_configured}` - service URL missing
    * `{:error, :extractor_token_not_configured}` - auth token missing
    * `{:error, {:extractor_error, status}}` - non-200 response
    * `{:error, {:request_failed, reason}}` - network/transport error
  """
  @callback extract(pdf_binary :: binary(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Checks the health of the extraction service.

  ## Returns
    * `{:ok, map()}` - health status map (e.g., `%{"status" => "ok"}`)
    * `{:error, :extractor_not_configured}` - service URL missing
    * `{:error, {:extractor_error, status}}` - non-200 response
    * `{:error, {:request_failed, reason}}` - network/transport error
  """
  @callback health() :: {:ok, map()} | {:error, term()}
end
