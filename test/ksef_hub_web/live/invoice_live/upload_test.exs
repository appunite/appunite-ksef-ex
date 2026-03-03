defmodule KsefHubWeb.InvoiceLive.UploadTest do
  # async: false because upload spawns Task.Supervisor.async_nolink which
  # doesn't propagate $callers, so Mox stubs need global mode.
  use KsefHubWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Invoices

  setup :set_mox_global
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
    test "renders upload form", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/upload")

      assert has_element?(view, "#upload-form")
      assert has_element?(view, "button[type='submit']", "Upload & Extract")
      assert has_element?(view, ~s(input[type="file"]))
    end

    test "does not show income/expense type selector", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/upload")

      refute has_element?(view, ~s(input[type="radio"]))
    end

    test "redirects reviewer to invoices", %{conn: _conn} do
      {:ok, reviewer} =
        Accounts.get_or_create_google_user(%{
          uid: "g-upload-reviewer",
          email: "reviewer-upload@example.com",
          name: "Reviewer"
        })

      company = insert(:company)
      insert(:membership, user: reviewer, company: company, role: :reviewer)

      conn = build_conn() |> log_in_user(reviewer, %{current_company_id: company.id})

      expected_path = "/c/#{company.id}/invoices"

      assert {:error, {:redirect, %{to: ^expected_path}}} =
               live(conn, ~p"/c/#{company.id}/invoices/upload")
    end

    test "redirects when user has no companies" do
      {:ok, no_company_user} =
        Accounts.get_or_create_google_user(%{
          uid: "g-upload-nocompany",
          email: "nocompany@example.com",
          name: "No Company"
        })

      conn = build_conn() |> log_in_user(no_company_user)

      # LiveAuth rejects access to a company the user doesn't belong to
      assert {:error, {:redirect, %{to: "/companies"}}} =
               live(conn, ~p"/c/#{Ecto.UUID.generate()}/invoices/upload")
    end
  end

  describe "file upload" do
    test "successful upload redirects to invoice show page", %{conn: conn, company: company} do
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
           "gross_amount" => "1230.00",
           "currency" => "PLN"
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/upload")

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

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r|/c/#{company.id}/invoices/[a-f0-9-]+|

      # Verify the created invoice is an expense
      [invoice_id] = Regex.run(~r|/invoices/([a-f0-9-]+)|, path, capture: :all_but_first)
      invoice = Invoices.get_invoice!(company.id, invoice_id)
      assert invoice.type == :expense
      assert invoice.source == :pdf_upload
      assert invoice.extraction_status == :complete
    end

    test "failed extraction creates invoice with failed status and redirects", %{
      conn: conn,
      company: company
    } do
      stub(KsefHub.InvoiceExtractor.Mock, :extract, fn _binary, _opts ->
        {:error, :extractor_not_configured}
      end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/upload")

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

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r|/c/#{company.id}/invoices/[a-f0-9-]+|

      # Verify the invoice was created with :failed extraction status
      [invoice_id] = Regex.run(~r|/invoices/([a-f0-9-]+)|, path, capture: :all_but_first)
      invoice = Invoices.get_invoice!(company.id, invoice_id)
      assert invoice.extraction_status == :failed
      assert invoice.source == :pdf_upload
    end

    test "upload without file shows error", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/upload")

      html = render_submit(view, "upload", %{})
      assert html =~ "Please select a PDF file"
    end
  end

  describe "index button visibility" do
    test "shows Upload PDF button for owner", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices")

      assert has_element?(view, ~s(a[href="/c/#{company.id}/invoices/upload"]), "Upload PDF")
    end

    test "hides Upload PDF button for reviewer" do
      {:ok, reviewer} =
        Accounts.get_or_create_google_user(%{
          uid: "g-upload-idx-rev",
          email: "reviewer-idx@example.com",
          name: "Reviewer"
        })

      company = insert(:company)
      insert(:membership, user: reviewer, company: company, role: :reviewer)

      conn = build_conn() |> log_in_user(reviewer, %{current_company_id: company.id})
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices")

      refute has_element?(view, ~s(a[href="/c/#{company.id}/invoices/upload"]))
    end
  end
end
