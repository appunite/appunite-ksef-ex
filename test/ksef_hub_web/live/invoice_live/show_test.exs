defmodule KsefHubWeb.InvoiceLive.ShowTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Invoices

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
    stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)
    :ok
  end

  describe "mount" do
    test "renders invoice detail page", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:ok, "<html>preview</html>"} end)

      {:ok, _view, html} = live(conn, ~p"/invoices/#{invoice.id}")
      assert html =~ invoice.invoice_number
      assert html =~ invoice.seller_name
      assert html =~ invoice.buyer_name
    end

    test "renders download dropdown with PDF and XML links", %{conn: conn, company: company} do
      xml = File.read!("test/support/fixtures/sample_income.xml")
      invoice = insert(:invoice, type: :income, xml_content: xml, company: company)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:ok, "<html>preview</html>"} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      assert has_element?(view, "div.dropdown")
      assert has_element?(view, ~s(a[href="/invoices/#{invoice.id}/pdf"]))
      assert has_element?(view, ~s(a[href="/invoices/#{invoice.id}/xml"]))
    end

    test "shows preview when xml_content is available", %{conn: conn, company: company} do
      xml = File.read!("test/support/fixtures/sample_income.xml")
      invoice = insert(:invoice, type: :income, xml_content: xml, company: company)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:ok, "<html>preview</html>"} end)

      {:ok, _view, html} = live(conn, ~p"/invoices/#{invoice.id}")
      assert html =~ "preview"
    end
  end

  describe "approve/reject" do
    setup :stub_pdf

    test "approve button shown for pending expense invoices", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")
      assert has_element?(view, "button", "Approve")
      assert has_element?(view, "button", "Reject")
    end

    test "approve button not shown for income invoices", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")
      refute has_element?(view, "button", "Approve")
    end

    test "clicking approve updates status", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      view |> element("button", "Approve") |> render_click()

      assert has_element?(view, "[class*=rounded-md]", "approved")
      refute has_element?(view, "button", "Approve")
      refute has_element?(view, "button", "Reject")
    end

    test "clicking reject updates status", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      view |> element("button", "Reject") |> render_click()

      assert has_element?(view, "[class*=rounded-md]", "rejected")
      refute has_element?(view, "button", "Approve")
      refute has_element?(view, "button", "Reject")
    end

    test "approve on income invoice is rejected", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      # Buttons aren't shown for income, but test the server-side guard via hook
      render_hook(view, "approve", %{})

      # Status should remain pending (not changed to approved)
      assert has_element?(view, "[class*=rounded-md]", "pending")
      refute has_element?(view, "[class*=rounded-md]", "approved")
    end

    test "already-approved invoice does not show action buttons", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, status: :approved, company: company)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      assert has_element?(view, "[class*=rounded-md]", "approved")
      refute has_element?(view, "button", "Approve")
      refute has_element?(view, "button", "Reject")
    end
  end

  describe "category and tags display" do
    setup :stub_pdf

    test "displays category name and emoji", %{conn: conn, company: company} do
      category = insert(:category, company: company, name: "finance:invoices", emoji: "💰")
      invoice = insert(:invoice, company: company, category: category)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")
      assert has_element?(view, "[data-testid=category-select]")
      html = render(view)
      assert html =~ "finance:invoices"
      assert html =~ "💰"
    end

    test "displays assigned tags", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "quarterly-report")
      invoice = insert(:invoice, company: company)
      insert(:invoice_tag, invoice: invoice, tag: tag)

      {:ok, _view, html} = live(conn, ~p"/invoices/#{invoice.id}")
      assert html =~ "quarterly-report"
    end

    test "shows needs_review prediction indicator", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company, prediction_status: :needs_review)

      {:ok, _view, html} = live(conn, ~p"/invoices/#{invoice.id}")
      assert html =~ "Review"
    end
  end

  describe "category editing" do
    setup :stub_pdf

    test "selecting a category updates the invoice", %{conn: conn, company: company} do
      category = insert(:category, company: company, name: "ops:hosting", emoji: "🖥")
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      view
      |> form("[data-testid=category-form]", %{"category_id" => category.id})
      |> render_change()

      html = render(view)
      assert html =~ "ops:hosting"

      updated = Invoices.get_invoice_with_details!(company.id, invoice.id)
      assert updated.category_id == category.id
      assert updated.prediction_status == :manual
    end

    test "clearing category sets it to nil", %{conn: conn, company: company} do
      category = insert(:category, company: company, name: "ops:clear-test")
      invoice = insert(:invoice, company: company, category: category)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      view
      |> form("[data-testid=category-form]", %{"category_id" => ""})
      |> render_change()

      updated = Invoices.get_invoice_with_details!(company.id, invoice.id)
      assert is_nil(updated.category_id)
    end
  end

  describe "tag editing" do
    setup :stub_pdf

    test "toggling a tag on adds it to the invoice", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "toggle-on")
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      view
      |> element(~s(input[phx-value-tag-id="#{tag.id}"]))
      |> render_click()

      tags = Invoices.list_invoice_tags(invoice.id)
      assert Enum.any?(tags, &(&1.id == tag.id))
    end

    test "toggling a tag off removes it from the invoice", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "toggle-off")
      invoice = insert(:invoice, company: company)
      insert(:invoice_tag, invoice: invoice, tag: tag)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      view
      |> element(~s(input[phx-value-tag-id="#{tag.id}"]))
      |> render_click()

      tags = Invoices.list_invoice_tags(invoice.id)
      refute Enum.any?(tags, &(&1.id == tag.id))
    end

    test "creating a new tag inline adds it to the invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      view
      |> element("form[phx-submit=create_and_add_tag]")
      |> render_submit(%{"name" => "brand-new-tag"})

      html = render(view)
      assert html =~ "brand-new-tag"

      tags = Invoices.list_invoice_tags(invoice.id)
      assert Enum.any?(tags, &(&1.name == "brand-new-tag"))
    end
  end

  describe "extraction status display" do
    test "shows extraction badge for partial invoice", %{conn: conn, company: company} do
      invoice =
        insert(:invoice, company: company, extraction_status: :partial, net_amount: nil)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, _view, html} = live(conn, ~p"/invoices/#{invoice.id}")
      assert html =~ "Incomplete"
      assert html =~ "missing data"
    end

    test "does not show extraction badge for complete invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company, extraction_status: :complete)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, _view, html} = live(conn, ~p"/invoices/#{invoice.id}")
      refute html =~ "Incomplete"
      refute html =~ "missing data"
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

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      html = view |> element("button", "Approve") |> render_click()
      assert html =~ "Cannot approve: missing required fields"
    end
  end

  describe "edit form" do
    test "shows edit form when Edit button is clicked", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")
      refute has_element?(view, "form[phx-submit=save_edit]")

      view |> element("button", "Edit") |> render_click()
      assert has_element?(view, "form[phx-submit=save_edit]")
    end

    test "edit form opens automatically for partial extraction", %{
      conn: conn,
      company: company
    } do
      invoice =
        insert(:invoice, company: company, extraction_status: :partial, net_amount: nil)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")
      assert has_element?(view, "form[phx-submit=save_edit]")
    end

    test "cancel edit returns to read-only view", %{conn: conn, company: company} do
      invoice =
        insert(:invoice, company: company, extraction_status: :partial, net_amount: nil)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")
      assert has_element?(view, "form[phx-submit=save_edit]")

      view |> element("button", "Cancel") |> render_click()
      refute has_element?(view, "form[phx-submit=save_edit]")
    end

    test "saving edit updates invoice and exits edit mode", %{conn: conn, company: company} do
      invoice =
        insert(:invoice,
          company: company,
          extraction_status: :partial,
          net_amount: nil,
          gross_amount: nil
        )

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      html =
        view
        |> form("form[phx-submit=save_edit]", %{
          "invoice" => %{
            "net_amount" => "1000.00",
            "gross_amount" => "1230.00"
          }
        })
        |> render_submit()

      assert html =~ "Invoice updated"
      refute has_element?(view, "form[phx-submit=save_edit]")
      # extraction status should now be complete, no warning banner
      refute html =~ "missing data"
    end

    test "shows validation errors for invalid NIP", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")
      view |> element("button", "Edit") |> render_click()

      html =
        view
        |> form("form[phx-submit=save_edit]", %{
          "invoice" => %{"seller_nip" => "abc"}
        })
        |> render_submit()

      assert html =~ "must be a 10-digit NIP"
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
      insert(:membership, user: reviewer, company: company, role: :reviewer)

      conn = build_conn() |> log_in_user(reviewer, %{current_company_id: company.id})
      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)
      %{conn: conn, company: company}
    end

    test "reviewer can view expense invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, _view, html} = live(conn, ~p"/invoices/#{invoice.id}")
      assert html =~ invoice.invoice_number
    end

    test "reviewer is redirected when viewing income invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company)

      assert {:error, {:redirect, %{to: "/invoices"}}} =
               live(conn, ~p"/invoices/#{invoice.id}")
    end
  end
end
