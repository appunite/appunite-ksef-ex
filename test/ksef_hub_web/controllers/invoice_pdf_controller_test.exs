defmodule KsefHubWeb.InvoicePdfControllerTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import Mox

  alias KsefHub.Accounts

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.get_or_create_google_user(%{
        uid: "g-pdf-ctrl-#{System.unique_integer([:positive])}",
        email: "pdftest@example.com",
        name: "PDF Test"
      })

    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)

    conn = log_in_user(conn, user, %{current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  describe "xml/2" do
    test "downloads XML with correct content-type and filename", %{conn: conn, company: company} do
      xml = "<Faktura>test</Faktura>"
      xml_file = insert(:file, content: xml, content_type: "application/xml")

      invoice =
        insert(:invoice,
          company: company,
          xml_file: xml_file,
          invoice_number: "FV/2025/001"
        )

      conn = get(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/xml")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/xml"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "FV_2025_001.xml"
      assert conn.resp_body == xml
    end

    test "redirects when invoice not found", %{conn: conn, company: company} do
      conn = get(conn, ~p"/c/#{company.id}/invoices/#{Ecto.UUID.generate()}/xml")

      assert redirected_to(conn) == "/c/#{company.id}/invoices"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not found"
    end

    test "redirects when user has no role for the company", %{conn: conn, user: user} do
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company)

      conn =
        conn
        |> recycle()
        |> log_in_user(user)
        |> get(~p"/c/#{other_company.id}/invoices/#{invoice.id}/xml")

      # User has no membership for other_company, so access is denied
      assert redirected_to(conn) == "/companies"
    end

    test "redirects when invoice belongs to different company", %{conn: conn, company: company} do
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company)

      conn = get(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/xml")

      assert redirected_to(conn) == "/c/#{company.id}/invoices"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not found"
    end
  end

  describe "xml/2 for pdf_upload invoices" do
    test "redirects with error when invoice has no xml_file", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      conn = get(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/xml")

      assert redirected_to(conn) == "/c/#{company.id}/invoices/#{invoice.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "No XML content"
    end
  end

  describe "show/2 (PDF)" do
    test "generates PDF from XML for KSeF invoices", %{conn: conn, company: company} do
      xml_file =
        insert(:file, content: "<Faktura>test</Faktura>", content_type: "application/xml")

      invoice =
        insert(:invoice,
          company: company,
          xml_file: xml_file,
          invoice_number: "FV/2025/002"
        )

      expect(KsefHub.PdfRenderer.Mock, :generate_pdf, fn _xml, _meta ->
        {:ok, "%PDF-fake-content"}
      end)

      conn = get(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/pdf")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/pdf"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "FV_2025_002.pdf"
      assert conn.resp_body == "%PDF-fake-content"
    end

    test "serves stored PDF for pdf_upload invoices", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company, invoice_number: "FV/PDF/001")

      conn = get(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/pdf")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/pdf"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "FV_PDF_001.pdf"
      assert conn.resp_body == "%PDF-1.4 fake content"
    end

    test "redirects when invoice has neither PDF nor XML", %{conn: conn, company: company} do
      invoice = insert(:manual_invoice, company: company)

      conn = get(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/pdf")

      assert redirected_to(conn) == "/c/#{company.id}/invoices/#{invoice.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "No PDF or XML"
    end
  end

  describe "show/2 inline (iframe preview)" do
    test "returns inline error when user has no role for company", %{conn: conn, user: _user} do
      # Create user with no companies
      {:ok, lonely_user} =
        Accounts.get_or_create_google_user(%{
          uid: "g-lonely-#{System.unique_integer([:positive])}",
          email: "lonely@example.com",
          name: "No Company"
        })

      fake_company_id = Ecto.UUID.generate()

      conn =
        conn
        |> recycle()
        |> log_in_user(lonely_user)
        |> get(~p"/c/#{fake_company_id}/invoices/#{Ecto.UUID.generate()}/pdf?inline=1")

      assert conn.status == 403
      assert conn.resp_body =~ "Access denied"
    end

    test "returns inline error when invoice not found", %{conn: conn, company: company} do
      conn = get(conn, ~p"/c/#{company.id}/invoices/#{Ecto.UUID.generate()}/pdf?inline=1")

      assert conn.status == 404
      assert conn.resp_body =~ "not found"
    end

    test "returns inline error when no PDF or XML content", %{conn: conn, company: company} do
      invoice = insert(:manual_invoice, company: company)

      conn = get(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/pdf?inline=1")

      assert conn.status == 422
      assert conn.resp_body =~ "No PDF or XML"
    end

    test "returns inline error when PDF generation fails", %{conn: conn, company: company} do
      xml_file =
        insert(:file, content: "<Faktura>test</Faktura>", content_type: "application/xml")

      invoice = insert(:invoice, company: company, xml_file: xml_file)

      expect(KsefHub.PdfRenderer.Mock, :generate_pdf, fn _xml, _meta ->
        {:error, :renderer_unavailable}
      end)

      conn = get(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/pdf?inline=1")

      assert conn.status == 422
      assert conn.resp_body =~ "PDF generation failed"
    end
  end
end
