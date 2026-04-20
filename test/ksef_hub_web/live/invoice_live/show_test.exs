defmodule KsefHubWeb.InvoiceLive.ShowTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Invoices
  alias KsefHub.Repo

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.get_or_create_google_user(%{
        uid: "g-show-1",
        email: "test@example.com",
        name: "Test"
      })

    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)

    conn = conn |> log_in_user(user, %{current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  defp stub_pdf(_context) do
    stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)
    :ok
  end

  describe "mount" do
    test "renders invoice detail page", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta ->
        {:ok, "<html>preview</html>"}
      end)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert html =~ invoice.invoice_number
      assert html =~ invoice.seller_name
      assert html =~ invoice.buyer_name
    end

    test "renders download dropdown with PDF and XML links", %{conn: conn, company: company} do
      xml = File.read!("test/support/fixtures/sample_income.xml")
      xml_file = insert(:file, content: xml, content_type: "application/xml")

      invoice =
        insert(:invoice, type: :income, xml_file: xml_file, company: company)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta ->
        {:ok, "<html>preview</html>"}
      end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      assert has_element?(view, "div.dropdown")
      assert has_element?(view, ~s(a[href="/c/#{company.id}/invoices/#{invoice.id}/pdf"]))
      assert has_element?(view, ~s(a[href="/c/#{company.id}/invoices/#{invoice.id}/xml"]))
    end

    test "shows preview when xml_file is available", %{conn: conn, company: company} do
      xml = File.read!("test/support/fixtures/sample_income.xml")
      xml_file = insert(:file, content: xml, content_type: "application/xml")

      invoice =
        insert(:invoice, type: :income, xml_file: xml_file, company: company)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta ->
        {:ok, "<html>preview</html>"}
      end)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert html =~ "preview"
    end
  end

  describe "breadcrumbs" do
    setup :stub_pdf

    test "shows type-specific breadcrumb for expense invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert html =~ ~s(href="/c/#{company.id}/invoices?type=expense")
      assert html =~ "Expense"
    end

    test "shows type-specific breadcrumb for income invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert html =~ ~s(href="/c/#{company.id}/invoices?type=income")
      assert html =~ "Income"
    end
  end

  describe "restricted badge" do
    setup :stub_pdf

    test "shows restricted badge for access-restricted invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, access_restricted: true, company: company)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert html =~ "restricted"
    end

    test "does not show restricted badge for unrestricted invoice", %{
      conn: conn,
      company: company
    } do
      invoice = insert(:invoice, type: :expense, access_restricted: false, company: company)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      # "restricted" should not appear as a badge (it may appear in other contexts like the access control section)
      refute html =~ ~r/<[^>]*variant="error"[^>]*>restricted</
    end
  end

  describe "Add payment button" do
    setup :stub_pdf

    test "does not show Add payment button in top action bar", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      refute html =~ ~r/<header[^>]*>.*Add payment.*<\/header>/s
    end
  end

  describe "Payment Requests section" do
    setup :stub_pdf

    test "shows payment requests linked to an expense invoice", %{
      conn: conn,
      company: company,
      user: user
    } do
      invoice = insert(:invoice, type: :expense, company: company)

      insert(:payment_request,
        company: company,
        created_by: user,
        invoice: invoice,
        title: "PR Vendor Payment",
        recipient_name: "PR Vendor",
        amount: Decimal.new("500.00"),
        status: :pending
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      html = view |> element(~s([data-testid="tab-payments"])) |> render_click()
      assert has_element?(view, "#payment-requests-section")
      assert html =~ "PR Vendor Payment"
      assert html =~ "500.00"
    end

    test "shows empty state when no payment requests exist for owner", %{
      conn: conn,
      company: company
    } do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s([data-testid="tab-payments"])) |> render_click()
      assert has_element?(view, "#payment-requests-section")
      assert has_element?(view, "#payment-requests-section a", "Add payment request")
      assert has_element?(view, "#payment-requests-section", "No payment requests yet")
    end

    test "hides payment requests section for accountant when none exist", %{company: company} do
      accountant = insert(:user)
      insert(:membership, user: accountant, company: company, role: :accountant)
      conn = build_conn() |> log_in_user(accountant, %{current_company_id: company.id})

      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      refute has_element?(view, "#payment-requests-section")
    end

    test "shows payment requests section for accountant when requests exist", %{
      company: company,
      user: user
    } do
      accountant = insert(:user)
      insert(:membership, user: accountant, company: company, role: :accountant)
      conn = build_conn() |> log_in_user(accountant, %{current_company_id: company.id})

      invoice = insert(:invoice, type: :expense, company: company)
      insert(:payment_request, invoice: invoice, company: company, created_by: user)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s([data-testid="tab-payments"])) |> render_click()
      assert has_element?(view, "#payment-requests-section")
      refute has_element?(view, "#payment-requests-section a", "Add")
    end

    test "shows paid badge and paid date for paid payment request", %{
      conn: conn,
      company: company,
      user: user
    } do
      invoice = insert(:invoice, type: :expense, company: company)

      insert(:payment_request,
        company: company,
        created_by: user,
        invoice: invoice,
        recipient_name: "Paid Vendor",
        status: :paid,
        paid_at: ~U[2026-03-10 12:00:00.000000Z]
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      html = view |> element(~s([data-testid="tab-payments"])) |> render_click()
      assert html =~ "paid"
      assert html =~ "2026-03-10"
    end
  end

  describe "copy_public_link" do
    setup :stub_pdf

    test "generates token and pushes clipboard event", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s([data-testid="tab-access"])) |> render_click()
      assert has_element?(view, ~s([data-testid="create-public-link"]))

      html = view |> element(~s([data-testid="create-public-link"])) |> render_click()

      assert html =~ "Public link created and copied to clipboard."
      assert has_element?(view, ~s([data-testid="copy-public-link"]))
    end

    test "is idempotent — reuses existing token for the same user", %{
      conn: conn,
      company: company,
      user: user
    } do
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s([data-testid="tab-access"])) |> render_click()
      view |> element(~s([data-testid="create-public-link"])) |> render_click()
      view |> element(~s([data-testid="copy-public-link"])) |> render_click()

      import Ecto.Query
      alias KsefHub.Invoices.InvoicePublicToken

      count =
        Repo.one(
          from pt in InvoicePublicToken,
            where: pt.invoice_id == ^invoice.id and pt.user_id == ^user.id,
            select: count()
        )

      assert count == 1
    end

    test "revoke_public_link deletes the token and returns the banner to disabled state", %{
      conn: conn,
      company: company,
      user: user
    } do
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s([data-testid="tab-access"])) |> render_click()
      view |> element(~s([data-testid="create-public-link"])) |> render_click()

      assert has_element?(view, ~s([data-testid="public-link-url"]))
      assert has_element?(view, ~s([data-testid="copy-public-link"]))

      html = view |> element(~s([data-testid="revoke-public-link"])) |> render_click()

      assert html =~ "Public link revoked."
      assert has_element?(view, ~s([data-testid="create-public-link"]))
      refute has_element?(view, ~s([data-testid="public-link-url"]))
      assert Invoices.get_public_token_for(invoice.id, user.id) == nil
    end

    test "copy_public_link without an active link flashes an error", %{
      conn: conn,
      company: company
    } do
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s([data-testid="tab-access"])) |> render_click()

      html = render_click(view, "copy_public_link")

      assert html =~ "No share link to copy"
    end

    test "accountant without update permission cannot create a share link", %{conn: _conn} do
      {:ok, accountant} =
        KsefHub.Accounts.get_or_create_google_user(%{
          uid: "g-accountant-share-1",
          email: "accountant-share@example.com",
          name: "Analyst Share"
        })

      company = insert(:company)
      insert(:membership, user: accountant, company: company, role: :accountant)

      conn = build_conn() |> log_in_user(accountant, %{current_company_id: company.id})
      invoice = insert(:invoice, type: :expense, company: company)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      html = render_click(view, "create_public_link")
      assert html =~ "permission to modify this invoice"
      assert Invoices.get_public_token_for(invoice.id, accountant.id) == nil
    end

    test "accountant without update permission cannot revoke a share link", %{conn: _conn} do
      {:ok, accountant} =
        KsefHub.Accounts.get_or_create_google_user(%{
          uid: "g-accountant-share-2",
          email: "accountant-share-2@example.com",
          name: "Analyst Share 2"
        })

      company = insert(:company)
      insert(:membership, user: accountant, company: company, role: :accountant)

      conn = build_conn() |> log_in_user(accountant, %{current_company_id: company.id})
      invoice = insert(:invoice, type: :expense, company: company)

      # Pre-seed a token as if an admin had created one
      {:ok, pt, _} = Invoices.ensure_public_token(invoice, accountant.id)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      html = render_click(view, "revoke_public_link")
      assert html =~ "permission to modify this invoice"
      # Token still exists — revoke was blocked
      assert Invoices.get_public_token_for(invoice.id, accountant.id).id == pt.id
    end
  end

  describe "approve/reject" do
    setup :stub_pdf

    test "approve button shown for pending expense invoices", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "button", "Approve")
      assert has_element?(view, "button", "Reject")
    end

    test "approve button not shown for income invoices", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      refute has_element?(view, "button", "Approve")
    end

    test "clicking approve updates status", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      view |> element("button", "Approve") |> render_click()

      assert has_element?(view, "[class*=rounded-md]", "approved")
      refute has_element?(view, "button", "Approve")
      refute has_element?(view, "button", "Reject")
    end

    test "clicking reject updates status", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      view |> element("button", "Reject") |> render_click()

      assert has_element?(view, "[class*=rounded-md]", "rejected")
      refute has_element?(view, "button", "Approve")
      refute has_element?(view, "button", "Reject")
    end

    test "approve on income invoice is rejected", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      # Buttons aren't shown for income, but test the server-side guard via hook
      render_hook(view, "approve", %{})

      # Status badge is hidden for income invoices, and status should not change to approved
      refute has_element?(view, "[class*=bg-success]", "approved")

      # Verify the invoice was not mutated in the database
      unchanged = Invoices.get_invoice!(company.id, invoice.id)
      assert unchanged.expense_approval_status == invoice.expense_approval_status
    end

    test "already-approved invoice does not show action buttons", %{conn: conn, company: company} do
      invoice =
        insert(:invoice, type: :expense, expense_approval_status: :approved, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      assert has_element?(view, "[class*=rounded-md]", "approved")
      refute has_element?(view, "button", "Approve")
      refute has_element?(view, "button", "Reject")
    end
  end

  describe "reset_status" do
    setup :stub_pdf

    test "reset button appears for approved expense invoices", %{conn: conn, company: company} do
      invoice =
        insert(:invoice, type: :expense, expense_approval_status: :approved, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "[data-testid=reset-status-btn]", "Reset Decision")
    end

    test "reset button appears for rejected expense invoices", %{conn: conn, company: company} do
      invoice =
        insert(:invoice, type: :expense, expense_approval_status: :rejected, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "[data-testid=reset-status-btn]", "Reset Decision")
    end

    test "reset button hidden for pending invoices", %{conn: conn, company: company} do
      invoice =
        insert(:invoice, type: :expense, expense_approval_status: :pending, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      refute has_element?(view, "[data-testid=reset-status-btn]")
    end

    test "clicking reset changes status back to pending", %{conn: conn, company: company} do
      invoice =
        insert(:invoice, type: :expense, expense_approval_status: :approved, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      view |> element("[data-testid=reset-status-btn]") |> render_click()

      assert has_element?(view, "[class*=rounded-md]", "pending")
      assert has_element?(view, "button", "Approve")
      assert has_element?(view, "button", "Reject")
    end
  end

  describe "exclude/include" do
    setup :stub_pdf

    test "exclude event marks invoice as excluded and shows badge", %{
      conn: conn,
      company: company
    } do
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      html = render_hook(view, "exclude", %{})

      assert html =~ "Invoice excluded."
      assert html =~ "excluded"

      updated = KsefHub.Repo.get!(KsefHub.Invoices.Invoice, invoice.id)
      assert updated.is_excluded == true
    end

    test "include event removes exclusion and hides badge", %{
      conn: conn,
      company: company
    } do
      invoice = insert(:invoice, company: company, is_excluded: true)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      html = render_hook(view, "include", %{})

      assert html =~ "Invoice included."

      updated = KsefHub.Repo.get!(KsefHub.Invoices.Invoice, invoice.id)
      assert updated.is_excluded == false
    end

    test "excluded badge visible on page load for excluded invoice", %{
      conn: conn,
      company: company
    } do
      invoice = insert(:invoice, company: company, is_excluded: true)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      assert html =~ "excluded"
    end
  end

  describe "classification display (read-only)" do
    setup :stub_pdf

    test "displays category name and emoji", %{conn: conn, company: company} do
      category =
        insert(:category,
          company: company,
          identifier: "finance:invoices",
          name: "Invoices",
          emoji: "💰"
        )

      invoice = insert(:invoice, type: :expense, company: company, category: category)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "[data-testid=category-display]")
      html = render(view)
      assert html =~ "Invoices"
      assert html =~ "💰"
    end

    test "shows 'No category' placeholder when nil", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company, category: nil)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "[data-testid=category-display]", "-")
    end

    test "displays assigned tags as badges", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company, tags: ["quarterly-report"])

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert html =~ "quarterly-report"
    end

    test "shows Edit link to classify page", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, ~s([data-testid="edit-classification"]))
    end

    test "shows needs_review prediction indicator", %{conn: conn, company: company} do
      invoice =
        insert(:invoice, type: :expense, company: company, prediction_status: :needs_review)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert html =~ "needs review"
    end

    test "hides prediction hints when prediction_predicted_at is nil", %{
      conn: conn,
      company: company
    } do
      invoice = insert(:invoice, type: :expense, company: company, prediction_predicted_at: nil)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      refute has_element?(view, ~s([data-testid="prediction-category-hint"]))
      refute has_element?(view, ~s([data-testid="prediction-tag-hint"]))
    end

    test "shows high-confidence prediction hint for category", %{conn: conn, company: company} do
      invoice =
        insert(:invoice,
          type: :expense,
          company: company,
          prediction_status: :predicted,
          prediction_expense_category_confidence: 0.92,
          prediction_expense_tag_confidence: 0.96,
          prediction_predicted_at: ~U[2026-03-11 12:00:00Z]
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, ~s([data-testid="prediction-category-hint"]))
      assert has_element?(view, ~s([data-testid="prediction-tag-hint"]))
      assert render(view) =~ "Predicted with 92.0% probability"
      assert render(view) =~ "Predicted with 96.0% probability"
    end

    test "shows low-confidence hint when below threshold", %{conn: conn, company: company} do
      invoice =
        insert(:invoice,
          type: :expense,
          company: company,
          prediction_status: :needs_review,
          prediction_expense_category_confidence: 0.30,
          prediction_expense_tag_confidence: 0.25,
          prediction_predicted_at: ~U[2026-03-11 12:00:00Z]
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, ~s([data-testid="prediction-category-hint"]))
      assert has_element?(view, ~s([data-testid="prediction-tag-hint"]))
      assert render(view) =~ "Could not predict category automatically"
      assert render(view) =~ "Could not predict tag automatically"
    end

    test "shows manually adjusted hint when prediction_status is manual", %{
      conn: conn,
      company: company
    } do
      invoice =
        insert(:invoice,
          type: :expense,
          company: company,
          prediction_status: :manual,
          prediction_expense_category_confidence: 0.92,
          prediction_expense_tag_confidence: 0.85,
          prediction_predicted_at: ~U[2026-03-11 12:00:00Z]
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, ~s([data-testid="prediction-category-hint"]))
      assert render(view) =~ "Manually adjusted"
      refute render(view) =~ "Predicted with"
    end
  end

  describe "extraction status display" do
    test "shows extraction badge for partial invoice", %{conn: conn, company: company} do
      invoice =
        insert(:invoice, company: company, extraction_status: :partial, net_amount: nil)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "[class*=rounded-md]", "incomplete")
      assert has_element?(view, ~s([data-testid="extraction-warning"]))
    end

    test "does not show extraction badge for complete invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company, extraction_status: :complete)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      refute has_element?(view, "[class*=rounded-md]", "incomplete")
      refute has_element?(view, ~s([data-testid="extraction-warning"]))
    end

    test "dismiss_extraction_warning removes the warning banner", %{
      conn: conn,
      company: company
    } do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :partial,
          net_amount: nil
        )

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, ~s([data-testid="extraction-warning"]))

      view |> element("button", "Dismiss") |> render_click()

      refute has_element?(view, ~s([data-testid="extraction-warning"]))
      refute has_element?(view, "[class*=rounded-md]", "incomplete")
    end

    test "approve shows specific error for partial extraction invoice", %{
      conn: conn,
      company: company
    } do
      invoice =
        insert(:invoice,
          company: company,
          type: :expense,
          extraction_status: :partial,
          net_amount: nil
        )

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      html = view |> element("button", "Approve") |> render_click()
      assert html =~ "extraction is incomplete"
    end

    test "accountant cannot dismiss extraction warning", %{conn: _conn} do
      {:ok, accountant} =
        Accounts.get_or_create_google_user(%{
          uid: "g-acct-dismiss-1",
          email: "accountant-dismiss@example.com",
          name: "Accountant"
        })

      company = insert(:company)
      insert(:membership, user: accountant, company: company, role: :accountant)

      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :partial,
          net_amount: nil
        )

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      conn =
        build_conn() |> log_in_user(accountant, %{current_company_id: company.id})

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, ~s([data-testid="extraction-warning"]))
      refute has_element?(view, "button", "Dismiss")

      # Forged event should be rejected by auth guard
      render_click(view, "dismiss_extraction_warning")

      assert has_element?(view, ~s([data-testid="extraction-warning"]))
      assert Repo.get!(KsefHub.Invoices.Invoice, invoice.id).extraction_status == :partial
    end
  end

  describe "edit form" do
    test "does not show edit button for KSeF invoices", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      refute has_element?(view, ~s([data-testid="edit-details-btn"]))
      assert has_element?(view, ~s([data-testid="ksef-locked-badge"]))
    end

    test "shows edit form when Edit button is clicked", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      refute has_element?(view, "form[phx-submit=save_edit]")

      view |> element(~s(button[phx-click="toggle_edit"]), "Edit") |> render_click()
      assert has_element?(view, "form[phx-submit=save_edit]")
    end

    test "edit form opens automatically for partial extraction", %{
      conn: conn,
      company: company
    } do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :partial,
          net_amount: nil
        )

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "form[phx-submit=save_edit]")
    end

    test "does not auto-edit for KSeF invoices even with partial extraction", %{
      conn: conn,
      company: company
    } do
      invoice =
        insert(:invoice, company: company, extraction_status: :partial, net_amount: nil)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      refute has_element?(view, "form[phx-submit=save_edit]")
    end

    test "cancel edit returns to read-only view", %{conn: conn, company: company} do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :partial,
          net_amount: nil
        )

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "form[phx-submit=save_edit]")

      view |> element("button", "Cancel") |> render_click()
      refute has_element?(view, "form[phx-submit=save_edit]")
    end

    test "saving edit updates invoice and exits edit mode", %{conn: conn, company: company} do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :partial,
          net_amount: nil,
          gross_amount: nil
        )

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      view
      |> form("form[phx-submit=save_edit]", %{
        "invoice" => %{
          "net_amount" => "1000.00",
          "gross_amount" => "1230.00"
        }
      })
      |> render_submit()

      assert has_element?(view, "#flash-info", "Invoice updated")
      refute has_element?(view, "form[phx-submit=save_edit]")
      # extraction status should now be complete, no warning banner
      refute has_element?(view, ~s([data-testid="extraction-warning"]))
    end

    test "accepts foreign tax ID in seller_nip field", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s(button[phx-click="toggle_edit"]), "Edit") |> render_click()

      view
      |> form("form[phx-submit=save_edit]", %{
        "invoice" => %{"seller_nip" => "FR61823475082"}
      })
      |> render_submit()

      # Form should be closed (edit successful)
      refute has_element?(view, "form[phx-submit=save_edit]")

      # Verify persistence
      updated = Invoices.get_invoice!(company.id, invoice.id)
      assert updated.seller_nip == "FR61823475082"
    end
  end

  describe "pdf_upload invoice" do
    setup :stub_pdf

    test "shows PDF preview iframe", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      assert html =~ ~s(src="/c/#{company.id}/invoices/#{invoice.id}/pdf?inline=1")
      assert html =~ "Invoice PDF preview"
    end

    test "shows download dropdown with PDF but not XML", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      assert has_element?(view, "div.dropdown")
      assert has_element?(view, ~s(a[href="/c/#{company.id}/invoices/#{invoice.id}/pdf"]))
      refute has_element?(view, ~s(a[href="/c/#{company.id}/invoices/#{invoice.id}/xml"]))
    end
  end

  describe "duplicate warning" do
    setup :stub_pdf

    test "shown when duplicate_of_id is set with link to original", %{
      conn: conn,
      company: company
    } do
      original = insert(:invoice, company: company)

      duplicate =
        insert(:pdf_upload_invoice,
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{duplicate.id}")

      assert has_element?(view, ~s([data-testid="duplicate-warning"]))

      assert has_element?(
               view,
               ~s(a[href="/c/#{company.id}/invoices/#{original.id}"]),
               "View original"
             )

      assert has_element?(view, "button", "Not a duplicate")
      assert has_element?(view, "button", "Confirm duplicate")
    end

    test "dismiss_duplicate replaces warning with dismissed note", %{conn: conn, company: company} do
      original = insert(:invoice, company: company)

      duplicate =
        insert(:pdf_upload_invoice,
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{duplicate.id}")

      view |> element("button", "Not a duplicate") |> render_click()

      refute has_element?(view, ~s([data-testid="duplicate-warning"]))
      assert has_element?(view, ~s([data-testid="duplicate-dismissed"]))

      assert has_element?(
               view,
               ~s(a[href="/c/#{company.id}/invoices/#{original.id}"]),
               "another invoice"
             )
    end

    test "confirm_duplicate shows confirmed state", %{conn: conn, company: company} do
      original = insert(:invoice, company: company)

      duplicate =
        insert(:pdf_upload_invoice,
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{duplicate.id}")

      view |> element("button", "Confirm duplicate") |> render_click()

      refute has_element?(view, ~s([data-testid="duplicate-warning"]))
      assert has_element?(view, ~s([data-testid="duplicate-confirmed"]))
    end

    test "not shown when duplicate_of_id is nil", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      refute has_element?(view, ~s([data-testid="duplicate-warning"]))
    end
  end

  describe "purchase_order display and editing" do
    setup :stub_pdf

    test "edit form includes purchase_order field", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s(button[phx-click="toggle_edit"]), "Edit") |> render_click()

      assert has_element?(view, "input#edit-purchase-order")
    end

    test "saving purchase_order via edit form persists the value", %{
      conn: conn,
      company: company
    } do
      invoice = insert(:pdf_upload_invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s(button[phx-click="toggle_edit"]), "Edit") |> render_click()

      view
      |> form("form[phx-submit=save_edit]", %{
        "invoice" => %{"purchase_order" => "PO-SAVED-123"}
      })
      |> render_submit()

      updated = Invoices.get_invoice!(company.id, invoice.id)
      assert updated.purchase_order == "PO-SAVED-123"
    end
  end

  describe "extraction fields display and editing" do
    setup :stub_pdf

    test "displays addresses when present", %{conn: conn, company: company} do
      invoice =
        insert(:invoice,
          company: company,
          seller_address: %{
            street: "ul. Testowa 1",
            city: "Warszawa",
            postal_code: nil,
            country: "PL"
          },
          buyer_address: %{street: "ul. Kupna 5", city: "Kraków", postal_code: nil, country: "PL"}
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "[data-testid=seller-address]", "ul. Testowa 1")
      assert has_element?(view, "[data-testid=buyer-address]", "ul. Kupna 5")
    end

    test "hides addresses when nil", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company, seller_address: nil, buyer_address: nil)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      refute has_element?(view, "[data-testid=seller-address]")
      refute has_element?(view, "[data-testid=buyer-address]")
    end

    test "displays sales_date and due_date when present", %{conn: conn, company: company} do
      invoice =
        insert(:invoice,
          company: company,
          sales_date: ~D[2025-01-14],
          due_date: ~D[2025-02-14]
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "[data-testid=sales-date]", "2025-01-14")
      assert has_element?(view, "[data-testid=due-date]", "2025-02-14")
    end

    test "displays iban when present", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company, iban: "PL61109010140000071219812874")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "[data-testid=iban]", "PL61109010140000071219812874")
    end

    test "edit form includes iban and date fields", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s(button[phx-click="toggle_edit"]), "Edit") |> render_click()

      assert has_element?(view, "#edit-sales-date")
      assert has_element?(view, "#edit-due-date")
      assert has_element?(view, "input#edit-iban")
    end

    test "saving extraction fields via edit form persists values", %{
      conn: conn,
      company: company
    } do
      invoice = insert(:pdf_upload_invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s(button[phx-click="toggle_edit"]), "Edit") |> render_click()

      view
      |> form("form[phx-submit=save_edit]", %{
        "invoice" => %{
          "sales_date" => "2025-06-01",
          "due_date" => "2025-07-01",
          "iban" => "PL61109010140000071219812874"
        }
      })
      |> render_submit()

      updated = Invoices.get_invoice!(company.id, invoice.id)
      assert updated.sales_date == ~D[2025-06-01]
      assert updated.due_date == ~D[2025-07-01]
      assert updated.iban == "PL61109010140000071219812874"
    end
  end

  describe "address editing" do
    setup :stub_pdf

    test "edit form shows address inputs pre-filled from existing data", %{
      conn: conn,
      company: company
    } do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          seller_address: %{
            "street" => "ul. Testowa 1",
            "city" => "Warszawa",
            "postal_code" => "00-001",
            "country" => "PL"
          }
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s(button[phx-click="toggle_edit"]), "Edit") |> render_click()

      assert has_element?(view, "input#edit-seller-address-street[value='ul. Testowa 1']")
      assert has_element?(view, "input#edit-seller-address-city[value='Warszawa']")
      assert has_element?(view, "input#edit-seller-address-postal-code[value='00-001']")
      assert has_element?(view, "input#edit-seller-address-country[value='PL']")
    end

    test "saving address fields persists them", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s(button[phx-click="toggle_edit"]), "Edit") |> render_click()

      view
      |> form("form[phx-submit=save_edit]", %{
        "invoice" => %{
          "seller_address" => %{
            "street" => "ul. Nowa 5",
            "city" => "Kraków",
            "postal_code" => "30-001",
            "country" => "PL"
          }
        }
      })
      |> render_submit()

      updated = Invoices.get_invoice!(company.id, invoice.id)
      assert updated.seller_address["street"] == "ul. Nowa 5"
      assert updated.seller_address["city"] == "Kraków"
      assert updated.seller_address["postal_code"] == "30-001"
      assert updated.seller_address["country"] == "PL"
    end

    test "clearing all address sub-fields stores nil", %{conn: conn, company: company} do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          seller_address: %{
            "street" => "ul. Testowa 1",
            "city" => "Warszawa",
            "postal_code" => "00-001",
            "country" => "PL"
          }
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s(button[phx-click="toggle_edit"]), "Edit") |> render_click()

      view
      |> form("form[phx-submit=save_edit]", %{
        "invoice" => %{
          "seller_address" => %{
            "street" => "",
            "city" => "",
            "postal_code" => "",
            "country" => ""
          }
        }
      })
      |> render_submit()

      updated = Invoices.get_invoice!(company.id, invoice.id)
      assert is_nil(updated.seller_address)
    end

    test "saving buyer_address persists and pre-fills correctly", %{
      conn: conn,
      company: company
    } do
      invoice = insert(:pdf_upload_invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s(button[phx-click="toggle_edit"]), "Edit") |> render_click()

      view
      |> form("form[phx-submit=save_edit]", %{
        "invoice" => %{
          "buyer_address" => %{
            "street" => "ul. Kupna 10",
            "city" => "Gdańsk",
            "postal_code" => "80-001",
            "country" => "PL"
          }
        }
      })
      |> render_submit()

      updated = Invoices.get_invoice!(company.id, invoice.id)
      assert updated.buyer_address["street"] == "ul. Kupna 10"
      assert updated.buyer_address["city"] == "Gdańsk"

      # Re-open edit form and verify pre-fill
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s(button[phx-click="toggle_edit"]), "Edit") |> render_click()

      assert has_element?(view, "input#edit-buyer-address-street[value='ul. Kupna 10']")
      assert has_element?(view, "input#edit-buyer-address-city[value='Gdańsk']")
    end
  end

  describe "reviewer role" do
    setup %{conn: _conn} do
      {:ok, reviewer} =
        Accounts.get_or_create_google_user(%{
          uid: "g-rev-show-1",
          email: "reviewer-show@example.com",
          name: "Reviewer"
        })

      company = insert(:company)
      insert(:membership, user: reviewer, company: company, role: :approver)

      conn = build_conn() |> log_in_user(reviewer, %{current_company_id: company.id})
      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)
      %{conn: conn, company: company}
    end

    test "reviewer can view expense invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert html =~ invoice.invoice_number
    end

    test "reviewer is redirected when viewing income invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company, access_restricted: true)

      expected_path = "/c/#{company.id}/invoices"

      assert {:error, {:redirect, %{to: ^expected_path}}} =
               live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
    end

    test "reviewer is redirected when viewing restricted expense invoice without grant", %{
      conn: conn,
      company: company
    } do
      invoice =
        insert(:invoice, type: :expense, company: company, access_restricted: true)

      expected_path = "/c/#{company.id}/invoices"

      assert {:error, {:redirect, %{to: ^expected_path}}} =
               live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
    end
  end

  describe "access control card" do
    setup :stub_pdf

    test "access control card is visible for owner", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s([data-testid="tab-access"])) |> render_click()
      assert has_element?(view, "#access-control-section")
      assert has_element?(view, "#access-mode-menu")
    end

    test "access control card is not visible for reviewer", %{conn: _conn} do
      {:ok, reviewer} =
        Accounts.get_or_create_google_user(%{
          uid: "g-rev-access-1",
          email: "reviewer-access@example.com",
          name: "Reviewer Access"
        })

      company = insert(:company)
      insert(:membership, user: reviewer, company: company, role: :approver)

      conn = build_conn() |> log_in_user(reviewer, %{current_company_id: company.id})
      invoice = insert(:invoice, type: :expense, company: company)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      refute has_element?(view, "#access-control-section")
      refute has_element?(view, "#access-mode-menu")
    end

    test "toggling access restriction works", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s([data-testid="tab-access"])) |> render_click()

      # Use the event directly since the button has JS command chain, not simple phx-click
      html = render_click(view, "toggle_access_restricted")

      assert html =~ "Invited only"
      assert html =~ "owners, admins, and accountants"

      updated = Invoices.get_invoice!(company.id, invoice.id)
      assert updated.access_restricted == true
    end

    test "team-default mode shows info message, not a user list", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company, access_restricted: false)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      html = view |> element(~s([data-testid="tab-access"])) |> render_click()

      assert html =~ "Team default"
      assert html =~ "Team members with invoice-viewing permission"
      refute html =~ "Granted by"
      refute html =~ "<thead"
    end

    test "invited-only mode with no grants shows empty state", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company, access_restricted: true)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      html = view |> element(~s([data-testid="tab-access"])) |> render_click()

      assert html =~ "No one invited"
      assert html =~ "No one has been invited yet"
      refute html =~ "Granted by"
    end

    test "invited-only mode renders grants table with user/role/granter/on columns", %{
      conn: conn,
      company: company,
      user: granter
    } do
      grantee = insert(:user, name: "Jane Doe", email: "jane@example.com")
      insert(:membership, user: grantee, company: company, role: :approver)

      invoice = insert(:invoice, type: :expense, company: company, access_restricted: true)

      {:ok, _grant} = Invoices.grant_access(invoice.id, grantee.id, granter.id)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      html = view |> element(~s([data-testid="tab-access"])) |> render_click()

      assert html =~ "1 person has access"
      assert html =~ "Jane Doe"
      assert html =~ "jane@example.com"
      assert html =~ "Approver"
      # Granter's name (test user from setup block)
      assert html =~ "Granted by"
      # Date is today in YYYY-MM-DD format
      today = Date.to_string(Date.utc_today())
      assert has_element?(view, "td", today)
    end

    test "grant and revoke access events work", %{conn: conn, company: company} do
      invoice =
        insert(:invoice, type: :expense, company: company, access_restricted: true)

      reviewer = insert(:user, name: "Granted Reviewer")
      insert(:membership, user: reviewer, company: company, role: :approver)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s([data-testid="tab-access"])) |> render_click()

      # Grant access
      view
      |> form("form[phx-submit=grant_access]", %{"user_id" => reviewer.id})
      |> render_submit()

      html = render(view)
      assert html =~ "Granted Reviewer"
      assert length(Invoices.list_access_grants(invoice.id)) == 1

      # Revoke access
      view
      |> element(~s(button[phx-click="revoke_access"][phx-value-user_id="#{reviewer.id}"]))
      |> render_click()

      assert Invoices.list_access_grants(invoice.id) == []
    end
  end

  describe "cost line display" do
    setup :stub_pdf

    test "shows cost line for expense invoice", %{conn: conn, company: company} do
      invoice =
        insert(:invoice, type: :expense, company: company, expense_cost_line: :service_delivery)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      assert has_element?(view, ~s([data-testid="cost-line-display"]))
      assert render(view) =~ "Service delivery"
    end

    test "shows fallback dash when cost line is nil", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, expense_cost_line: nil, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      assert has_element?(view, ~s([data-testid="cost-line-display"]))
      assert render(view) =~ "-"
    end

    test "does not show cost line section for income invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      refute has_element?(view, ~s([data-testid="cost-line-display"]))
    end
  end

  describe "project tag display" do
    setup :stub_pdf

    test "shows project tag for expense invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company, project_tag: "Alpha")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      assert has_element?(view, ~s([data-testid="project-tag-display"]))
      assert render(view) =~ "Alpha"
    end

    test "shows project tag for income invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company, project_tag: "Beta")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      assert has_element?(view, ~s([data-testid="project-tag-display"]))
      assert render(view) =~ "Beta"
    end

    test "does not show project tag badge when nil", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company, project_tag: nil)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      refute has_element?(view, ~s([data-testid="project-tag-display"]))
    end
  end

  describe "Notes tab" do
    setup :stub_pdf

    test "renders the empty state with Add note CTA when the invoice has no note", %{
      conn: conn,
      company: company
    } do
      invoice = insert(:invoice, company: company, note: nil)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s([data-testid="tab-notes"])) |> render_click()

      assert has_element?(view, "#notes-section", "No notes yet")
      assert has_element?(view, "#notes-section button", "Add note")
    end

    test "renders the existing note with an Edit affordance when one is present", %{
      conn: conn,
      company: company
    } do
      invoice = insert(:invoice, company: company, note: "Vendor confirmed scope on 2026-04-15.")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s([data-testid="tab-notes"])) |> render_click()

      refute has_element?(view, "#notes-section", "No notes yet")
      assert has_element?(view, "#notes-section", "Vendor confirmed scope")
      assert has_element?(view, "#notes-section button", "Edit")
    end

    test "tab pill reports 0 when no note, 1 when a note exists", %{
      conn: conn,
      company: company
    } do
      empty = insert(:invoice, company: company, note: nil)
      filled = insert(:invoice, company: company, note: "anything")

      {:ok, empty_view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{empty.id}")
      {:ok, filled_view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{filled.id}")

      assert has_element?(empty_view, ~s([data-testid="tab-notes"]), "0")
      assert has_element?(filled_view, ~s([data-testid="tab-notes"]), "1")
    end
  end

  describe "Comments tab" do
    setup :stub_pdf

    test "renders the empty state with Write a comment CTA", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s([data-testid="tab-comments"])) |> render_click()

      assert has_element?(view, "[role=tabpanel]", "Start the conversation")
      assert has_element?(view, "button", "Write a comment")
      assert has_element?(view, "textarea#comment-composer-body")
    end

    test "renders existing comments with author and body", %{
      conn: conn,
      company: company,
      user: user
    } do
      invoice = insert(:invoice, company: company)

      comment =
        insert(:invoice_comment, invoice: invoice, user: user, body: "Waiting for approval.")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      html = view |> element(~s([data-testid="tab-comments"])) |> render_click()

      assert has_element?(view, "#comment-#{comment.id}")
      assert html =~ "Waiting for approval."
      assert html =~ user.name
    end

    test "submitting a comment refreshes the tab count pill in place", %{
      conn: conn,
      company: company
    } do
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element(~s([data-testid="tab-comments"])) |> render_click()

      # Tab starts at 0
      assert has_element?(view, ~s([data-testid="tab-comments"]), "0")

      view
      |> form("#comment-form-0", %{"body" => "Adding context."})
      |> render_submit()

      assert has_element?(view, ~s([data-testid="tab-comments"]), "1")
      assert render(view) =~ "Adding context."
    end
  end

  describe "select_tab event" do
    setup :stub_pdf

    test "switching tab updates the active indicator", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company)
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      # Activity is the initial active tab.
      assert view
             |> element(~s([data-testid="tab-activity"][aria-selected="true"]))
             |> has_element?()

      view |> element(~s([data-testid="tab-comments"])) |> render_click()

      assert view
             |> element(~s([data-testid="tab-comments"][aria-selected="true"]))
             |> has_element?()

      refute view
             |> element(~s([data-testid="tab-activity"][aria-selected="true"]))
             |> has_element?()
    end

    test "unknown tab id is a no-op and does not crash", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company)
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      # A tampered client could submit any string — including something that is not an existing atom.
      render_click(view, "select_tab", %{"id" => "definitely_not_a_real_tab_#{System.unique_integer([:positive])}"})

      assert view
             |> element(~s([data-testid="tab-activity"][aria-selected="true"]))
             |> has_element?()
    end

    test "selecting a hidden tab is a no-op", %{company: company} do
      # Accountant does not see the access tab (can_mutate=false, can_manage_access=false).
      {:ok, accountant} =
        Accounts.get_or_create_google_user(%{
          uid: "g-select-tab-hidden",
          email: "select-tab-hidden@example.com",
          name: "Accountant Hidden"
        })

      insert(:membership, user: accountant, company: company, role: :accountant)
      conn = build_conn() |> log_in_user(accountant, %{current_company_id: company.id})
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      refute has_element?(view, ~s([data-testid="tab-access"]))

      render_click(view, "select_tab", %{"id" => "access"})

      assert view
             |> element(~s([data-testid="tab-activity"][aria-selected="true"]))
             |> has_element?()
    end
  end
end
