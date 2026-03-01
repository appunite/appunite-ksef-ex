defmodule KsefHubWeb.InvoiceLive.UploadTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  import KsefHub.Factory

  alias KsefHub.Accounts

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.get_or_create_google_user(%{
        uid: "g-upload-1",
        email: "uploader@example.com",
        name: "Uploader"
      })

    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)

    conn = conn |> log_in_user(user, %{current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  describe "mount" do
    test "renders upload form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/invoices/upload")

      assert html =~ "Upload PDF Invoice"
      assert html =~ "Upload &amp; Extract"
      assert html =~ "Expense"
      assert html =~ "Income"
    end

    test "defaults to expense type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/invoices/upload")

      assert has_element?(view, ~s(input[type="radio"][value="expense"][checked]))
    end
  end

  describe "type selection" do
    test "can switch to income type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/invoices/upload")

      view |> element(~s(input[value="income"])) |> render_click()

      assert has_element?(view, ~s(input[type="radio"][value="income"][checked]))
    end
  end

  describe "file upload" do
    test "successful upload redirects to invoice show page", %{conn: conn} do
      stub(KsefHub.InvoiceExtractor.Mock, :extract, fn _binary, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "Test Seller",
           "buyer_nip" => "0987654321",
           "buyer_name" => "Test Buyer",
           "invoice_number" => "FV/2025/1",
           "issue_date" => "2025-01-15",
           "net_amount" => "1000.00",
           "vat_amount" => "230.00",
           "gross_amount" => "1230.00",
           "currency" => "PLN"
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/invoices/upload")

      pdf_content = "%PDF-1.4 test content"

      view
      |> file_input("#upload-form", :invoice_pdf, [
        %{
          name: "test-invoice.pdf",
          content: pdf_content,
          type: "application/pdf"
        }
      ])
      |> render_upload("test-invoice.pdf")

      render_submit(view, "upload", %{})

      # The async task runs and redirects
      {path, _flash} = assert_redirect(view)
      assert path =~ ~r|/invoices/[a-f0-9-]+|
    end

    test "failed extraction still creates invoice and redirects", %{conn: conn} do
      stub(KsefHub.InvoiceExtractor.Mock, :extract, fn _binary, _opts ->
        {:error, :extractor_not_configured}
      end)

      {:ok, view, _html} = live(conn, ~p"/invoices/upload")

      pdf_content = "%PDF-1.4 test content"

      view
      |> file_input("#upload-form", :invoice_pdf, [
        %{
          name: "broken.pdf",
          content: pdf_content,
          type: "application/pdf"
        }
      ])
      |> render_upload("broken.pdf")

      render_submit(view, "upload", %{})

      # Even failed extraction creates an invoice with :failed status
      {path, _flash} = assert_redirect(view)
      assert path =~ ~r|/invoices/[a-f0-9-]+|
    end

    test "upload without file shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/invoices/upload")

      html = render_submit(view, "upload", %{})
      assert html =~ "Please select a PDF file"
    end
  end

  describe "show page integration" do
    test "pdf_upload invoice shows PDF preview iframe", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, _view, html} = live(conn, ~p"/invoices/#{invoice.id}")

      assert html =~ ~s(src="/invoices/#{invoice.id}/pdf")
      assert html =~ "Invoice PDF preview"
    end

    test "pdf_upload invoice shows download dropdown", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      assert has_element?(view, "div.dropdown")
      assert has_element?(view, ~s(a[href="/invoices/#{invoice.id}/pdf"]))
      # No XML link for pdf_upload invoices
      refute has_element?(view, ~s(a[href="/invoices/#{invoice.id}/xml"]))
    end

    test "duplicate warning shown when duplicate_of_id is set", %{conn: conn, company: company} do
      original = insert(:invoice, company: company)

      duplicate =
        insert(:pdf_upload_invoice, company: company, duplicate_of_id: original.id)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{duplicate.id}")

      assert has_element?(view, ~s([data-testid="duplicate-warning"]))
    end

    test "no duplicate warning when duplicate_of_id is nil", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      refute has_element?(view, ~s([data-testid="duplicate-warning"]))
    end
  end
end
