defmodule KsefHub.Pdf.Behaviour do
  @moduledoc """
  Behaviour for PDF generation pipeline.
  """

  @callback generate_html(xml_content :: String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback generate_pdf(html :: String.t()) :: {:ok, binary()} | {:error, term()}
end
