defmodule KsefHub.Pdf do
  @moduledoc """
  PDF generation pipeline. Delegates to the ksef-pdf microservice for both
  HTML preview and PDF generation from FA(3) XML.
  """

  @behaviour KsefHub.Pdf.Behaviour

  alias KsefHub.Pdf.KsefPdfService

  @doc """
  Generates an HTML preview of FA(3) XML via the ksef-pdf microservice.
  """
  @spec generate_html(String.t()) :: {:ok, String.t()} | {:error, term()}
  @spec generate_html(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  @impl true
  def generate_html(xml_content, metadata \\ %{}) do
    KsefPdfService.generate_html(xml_content, metadata)
  end

  @doc """
  Generates a PDF from FA(3) XML via the ksef-pdf microservice.
  """
  @spec generate_pdf(String.t()) :: {:ok, binary()} | {:error, term()}
  @spec generate_pdf(String.t(), map()) :: {:ok, binary()} | {:error, term()}
  @impl true
  def generate_pdf(xml_content, metadata \\ %{}) do
    KsefPdfService.generate_pdf(xml_content, metadata)
  end
end
