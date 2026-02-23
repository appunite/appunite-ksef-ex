defmodule KsefHub.Unstructured.Behaviour do
  @moduledoc """
  Behaviour for the au-ksef-unstructured PDF extraction sidecar.

  Defines callbacks for extracting structured invoice data from PDF files
  and checking the health of the extraction service.
  """

  @callback extract(pdf_binary :: binary(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @callback health() :: {:ok, map()} | {:error, term()}
end
