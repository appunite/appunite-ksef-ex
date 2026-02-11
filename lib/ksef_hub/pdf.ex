defmodule KsefHub.Pdf do
  @moduledoc """
  PDF generation pipeline. Orchestrates Xsltproc (XML → HTML) and Gotenberg (HTML → PDF)
  with fallback to a basic HTML template when xsltproc is unavailable.
  """

  @behaviour KsefHub.Pdf.Behaviour

  require Logger

  alias KsefHub.Pdf.{FallbackTemplate, Gotenberg, Xsltproc}

  @doc """
  Transforms FA(3) XML into HTML using xsltproc with the gov.pl stylesheet.
  Falls back to a basic HTML template when xsltproc is unavailable.
  """
  @spec generate_html(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  @impl true
  def generate_html(xml_content, metadata \\ %{}) do
    case Xsltproc.transform(xml_content, metadata) do
      {:ok, html} ->
        {:ok, html}

      {:error, _reason} ->
        Logger.debug("Xsltproc failed, using fallback template")
        FallbackTemplate.render(xml_content, metadata)
    end
  end

  @doc """
  Converts HTML into a PDF binary via the Gotenberg sidecar.
  """
  @spec generate_pdf(String.t()) :: {:ok, binary()} | {:error, term()}
  @impl true
  def generate_pdf(html) do
    Gotenberg.convert(html)
  end
end
