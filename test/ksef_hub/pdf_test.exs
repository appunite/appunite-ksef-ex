defmodule KsefHub.PdfTest do
  use ExUnit.Case, async: true

  alias KsefHub.Pdf

  @sample_xml File.read!("test/support/fixtures/sample_income.xml")

  describe "generate_html/1" do
    test "falls back to template when xsltproc fails" do
      # Xsltproc will fail because XSL path is configured to a non-existent path
      # or xsltproc is not installed. The fallback template should work.
      Application.put_env(:ksef_hub, :xsl_path, "/nonexistent/path.xsl")

      try do
        assert {:ok, html} = Pdf.generate_html(@sample_xml)
        assert html =~ "FV/2025/001"
        assert html =~ "Testowa Firma Sp. z o.o."
      after
        Application.delete_env(:ksef_hub, :xsl_path)
      end
    end

    test "returns error for completely invalid XML" do
      Application.put_env(:ksef_hub, :xsl_path, "/nonexistent/path.xsl")

      try do
        assert {:error, _} = Pdf.generate_html("")
      after
        Application.delete_env(:ksef_hub, :xsl_path)
      end
    end
  end

  describe "behaviour" do
    test "implements Pdf.Behaviour callbacks" do
      behaviours =
        KsefHub.Pdf.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert KsefHub.Pdf.Behaviour in behaviours
    end
  end
end
