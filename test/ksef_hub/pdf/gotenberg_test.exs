defmodule KsefHub.Pdf.GotenbergTest do
  use ExUnit.Case, async: false

  alias KsefHub.Pdf.Gotenberg

  describe "convert/1" do
    test "returns error when gotenberg is not configured" do
      original = Application.get_env(:ksef_hub, :gotenberg_url)
      Application.delete_env(:ksef_hub, :gotenberg_url)

      try do
        assert {:error, :gotenberg_not_configured} = Gotenberg.convert("<html></html>")
      after
        if original, do: Application.put_env(:ksef_hub, :gotenberg_url, original)
      end
    end

    @tag :integration
    test "converts HTML to PDF via Gotenberg sidecar" do
      html = "<html><body><h1>Test Invoice</h1></body></html>"
      assert {:ok, pdf_binary} = Gotenberg.convert(html)
      assert <<"%PDF", _rest::binary>> = pdf_binary
    end
  end
end
