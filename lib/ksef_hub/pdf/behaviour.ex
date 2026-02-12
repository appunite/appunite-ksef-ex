defmodule KsefHub.Pdf.Behaviour do
  @moduledoc """
  Behaviour for PDF generation pipeline.
  """

  @callback generate_html(xml_content :: String.t(), metadata :: map()) ::
              {:ok, String.t()} | {:error, term()}
  @callback generate_pdf(xml_content :: String.t(), metadata :: map()) ::
              {:ok, binary()} | {:error, term()}
end
