defmodule KsefHub.Unstructured.Behaviour do
  @moduledoc """
  Behaviour for the au-ksef-unstructured PDF extraction sidecar.

  Defines callbacks for extracting structured invoice data from PDF files
  and checking the health of the extraction service.
  """

  @doc """
  Extracts structured invoice data from a PDF binary.

  Sends the PDF to the extraction service and returns a string-keyed map
  of extracted fields (e.g., `"seller_nip"`, `"issue_date"`, `"net_amount"`).

  ## Options
    * `:filename` - original filename for the PDF (default: `"invoice.pdf"`)

  ## Returns
    * `{:ok, map()}` - extracted fields as string-keyed map
    * `{:error, :unstructured_service_not_configured}` - service URL missing
    * `{:error, :unstructured_token_not_configured}` - auth token missing
    * `{:error, {:unstructured_service_error, status}}` - non-200 response
    * `{:error, {:request_failed, reason}}` - network/transport error
  """
  @callback extract(pdf_binary :: binary(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Checks the health of the extraction service.

  ## Returns
    * `{:ok, map()}` - health status map (e.g., `%{"status" => "ok"}`)
    * `{:error, :unstructured_service_not_configured}` - service URL missing
    * `{:error, {:unstructured_service_error, status}}` - non-200 response
    * `{:error, {:request_failed, reason}}` - network/transport error
  """
  @callback health() :: {:ok, map()} | {:error, term()}
end
