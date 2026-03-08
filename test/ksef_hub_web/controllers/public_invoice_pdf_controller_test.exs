defmodule KsefHubWeb.PublicInvoicePdfControllerTest do
  use KsefHubWeb.ConnCase, async: true

  import Mox

  import KsefHub.Factory

  alias KsefHub.Invoices

  setup :set_mox_from_context
  setup :verify_on_exit!

  defp create_invoice_with_token(_context) do
    company = insert(:company)
    pdf_file = insert(:file, content: "%PDF-fake-content", content_type: "application/pdf")
    invoice = insert(:invoice, company: company, pdf_file: pdf_file)
    {:ok, invoice} = Invoices.generate_public_token(invoice)

    %{company: company, invoice: invoice, token: invoice.public_token}
  end

  describe "show/2" do
    setup :create_invoice_with_token

    test "serves PDF inline with valid token", %{conn: conn, invoice: invoice, token: token} do
      conn = get(conn, ~p"/public/invoices/#{invoice.id}/pdf?token=#{token}&inline=1")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/pdf"
      assert conn.resp_body == "%PDF-fake-content"
    end

    test "returns 404 for invalid token", %{conn: conn, invoice: invoice} do
      conn = get(conn, ~p"/public/invoices/#{invoice.id}/pdf?token=bogus")

      assert conn.status == 404
    end

    test "returns 404 for missing token", %{conn: conn, invoice: invoice} do
      conn = get(conn, ~p"/public/invoices/#{invoice.id}/pdf")

      assert conn.status == 404
    end

    test "returns 404 for ID/token mismatch", %{conn: conn, token: token} do
      other_invoice = insert(:invoice)

      conn = get(conn, ~p"/public/invoices/#{other_invoice.id}/pdf?token=#{token}")

      assert conn.status == 404
    end

    test "generates PDF from XML when no pdf_file", %{conn: conn} do
      company = insert(:company)
      xml_file = insert(:file, content: "<xml>data</xml>", content_type: "application/xml")
      invoice = insert(:invoice, company: company, xml_file: xml_file, pdf_file: nil)
      {:ok, invoice} = Invoices.generate_public_token(invoice)

      stub(KsefHub.PdfRenderer.Mock, :generate_pdf, fn _xml, _meta ->
        {:ok, "%PDF-generated"}
      end)

      conn =
        get(conn, ~p"/public/invoices/#{invoice.id}/pdf?token=#{invoice.public_token}&inline=1")

      assert conn.status == 200
      assert conn.resp_body == "%PDF-generated"
    end
  end
end
