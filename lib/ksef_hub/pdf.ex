defmodule KsefHub.Pdf do
  @moduledoc """
  PDF generation pipeline. Orchestrates Xsltproc (XML → HTML) and Gotenberg (HTML → PDF)
  with fallback to a basic HTML template when xsltproc is unavailable.
  """

  @behaviour KsefHub.Pdf.Behaviour

  alias KsefHub.Pdf.{Xsltproc, Gotenberg, FallbackTemplate}

  @impl true
  def generate_html(xml_content) do
    case Xsltproc.transform(xml_content) do
      {:ok, html} -> {:ok, html}
      {:error, _} -> FallbackTemplate.render(xml_content)
    end
  end

  @impl true
  def generate_pdf(html) do
    Gotenberg.convert(html)
  end
end
