defmodule KsefHub.Pdf.XsltprocTest do
  use ExUnit.Case, async: true

  alias KsefHub.Pdf.Xsltproc

  @sample_xml File.read!("test/support/fixtures/sample_income.xml")

  describe "transform/1" do
    @tag :integration
    test "transforms FA(3) XML to HTML with xsltproc" do
      xsl_path = Path.join(:code.priv_dir(:ksef_hub), "xsl/fa3-styl.xsl")

      if File.exists?(xsl_path) and System.find_executable("xsltproc") do
        assert {:ok, html} = Xsltproc.transform(@sample_xml)
        assert html =~ "<html"
        assert html =~ "FV/2025/001"
      end
    end

    test "returns error when XSL file not found" do
      Application.put_env(:ksef_hub, :xsl_path, "/nonexistent/path.xsl")

      try do
        assert {:error, :xsl_not_found} = Xsltproc.transform(@sample_xml)
      after
        Application.delete_env(:ksef_hub, :xsl_path)
      end
    end
  end
end
