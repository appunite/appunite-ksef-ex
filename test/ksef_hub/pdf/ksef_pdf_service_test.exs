defmodule KsefHub.Pdf.KsefPdfServiceTest do
  use ExUnit.Case, async: false

  alias KsefHub.Pdf.KsefPdfService

  @sample_xml File.read!("test/support/fixtures/sample_income.xml")

  describe "generate_pdf/2" do
    test "returns error when ksef_pdf_url is not configured" do
      original = Application.get_env(:ksef_hub, :ksef_pdf_url)
      Application.delete_env(:ksef_hub, :ksef_pdf_url)

      try do
        assert {:error, :ksef_pdf_not_configured} = KsefPdfService.generate_pdf(@sample_xml)
      after
        if original, do: Application.put_env(:ksef_hub, :ksef_pdf_url, original)
      end
    end

    @tag :integration
    test "generates PDF from FA(3) XML via ksef-pdf service" do
      assert {:ok, pdf_binary} = KsefPdfService.generate_pdf(@sample_xml, %{ksef_number: "1234"})
      assert <<"%PDF", _rest::binary>> = pdf_binary
    end
  end

  describe "generate_html/2" do
    test "returns error when ksef_pdf_url is not configured" do
      original = Application.get_env(:ksef_hub, :ksef_pdf_url)
      Application.delete_env(:ksef_hub, :ksef_pdf_url)

      try do
        assert {:error, :ksef_pdf_not_configured} = KsefPdfService.generate_html(@sample_xml)
      after
        if original, do: Application.put_env(:ksef_hub, :ksef_pdf_url, original)
      end
    end

    @tag :integration
    test "generates HTML from FA(3) XML via ksef-pdf service" do
      assert {:ok, html} = KsefPdfService.generate_html(@sample_xml, %{ksef_number: "1234"})
      assert html =~ "<html"
    end
  end
end
