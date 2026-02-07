defmodule KsefHub.PdfTest do
  use ExUnit.Case, async: false

  alias KsefHub.Pdf

  @sample_xml File.read!("test/support/fixtures/sample_income.xml")

  setup do
    prev = Application.fetch_env(:ksef_hub, :xsl_path)
    Application.put_env(:ksef_hub, :xsl_path, "/nonexistent/path.xsl")

    on_exit(fn ->
      case prev do
        {:ok, val} -> Application.put_env(:ksef_hub, :xsl_path, val)
        :error -> Application.delete_env(:ksef_hub, :xsl_path)
      end
    end)

    :ok
  end

  describe "generate_html/1" do
    test "falls back to template when xsltproc fails" do
      assert {:ok, html} = Pdf.generate_html(@sample_xml)
      assert html =~ "FV/2025/001"
      assert html =~ "Testowa Firma Sp. z o.o."
    end

    test "returns error for completely invalid XML" do
      assert {:error, _} = Pdf.generate_html("")
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
