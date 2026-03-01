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

      conn = get(conn, ~p"/invoices/#{invoice.id}/xml")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/xml"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "FV_2025_001.xml"
      assert conn.resp_body == xml
    end

    test "redirects when invoice not found", %{conn: conn} do
      conn = get(conn, ~p"/invoices/#{Ecto.UUID.generate()}/xml")

      assert redirected_to(conn) == "/invoices"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not found"
    end

    test "redirects when no company selected", %{conn: conn, user: user} do
      invoice = insert(:invoice)

      conn =
        conn
        |> recycle()
        |> log_in_user(user)
        |> get(~p"/invoices/#{invoice.id}/xml")

      assert redirected_to(conn) == "/companies"
    end

    test "redirects when invoice belongs to different company", %{conn: conn} do
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company)

      conn = get(conn, ~p"/invoices/#{invoice.id}/xml")

      assert redirected_to(conn) == "/invoices"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not found"
    end
  end

  describe "show/2 (PDF)" do
    test "generates and sends PDF", %{conn: conn, company: company} do
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

      conn = get(conn, ~p"/invoices/#{invoice.id}/pdf")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/pdf"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "FV_2025_002.pdf"
      assert conn.resp_body == "%PDF-fake-content"
    end
  end
end
