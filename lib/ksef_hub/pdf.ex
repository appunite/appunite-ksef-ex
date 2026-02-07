defmodule KsefHub.Pdf do
  @moduledoc """
  PDF generation pipeline. Orchestrates Xsltproc (XML → HTML) and Gotenberg (HTML → PDF)
  with fallback to a basic HTML template when xsltproc is unavailable.
  """

  @behaviour KsefHub.Pdf.Behaviour

  require Logger

  alias KsefHub.Pdf.{FallbackTemplate, Gotenberg, Xsltproc}

  @impl true
  def generate_html(xml_content) do
    case Xsltproc.transform(xml_content) do
      {:ok, html} ->
        {:ok, html}

      {:error, _reason} ->
        Logger.debug("Xsltproc failed, using fallback template")
        FallbackTemplate.render(xml_content)
    end
  end

  @impl true
  def generate_pdf(html) do
    Gotenberg.convert(html)
  end
end
