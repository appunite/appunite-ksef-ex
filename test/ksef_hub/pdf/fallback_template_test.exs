defmodule KsefHub.Pdf.FallbackTemplateTest do
  use ExUnit.Case, async: true

  alias KsefHub.Pdf.FallbackTemplate

  @sample_xml File.read!("test/support/fixtures/sample_income.xml")

  describe "render/1" do
    test "renders valid HTML from FA(3) XML" do
      assert {:ok, html} = FallbackTemplate.render(@sample_xml)
      assert html =~ "<!DOCTYPE html>"
      assert html =~ "FV/2025/001"
      assert html =~ "Testowa Firma Sp. z o.o."
      assert html =~ "1234567890"
    end

    test "includes buyer information" do
      assert {:ok, html} = FallbackTemplate.render(@sample_xml)
      assert html =~ "0987654321"
    end

    test "includes line items" do
      assert {:ok, html} = FallbackTemplate.render(@sample_xml)
      assert html =~ "programistyczne"
    end

    test "includes totals" do
      assert {:ok, html} = FallbackTemplate.render(@sample_xml)
      assert html =~ "12300.00"
      assert html =~ "PLN"
    end

    test "returns error for invalid XML" do
      assert {:error, _} = FallbackTemplate.render("<not-valid>")
    end
  end
end
