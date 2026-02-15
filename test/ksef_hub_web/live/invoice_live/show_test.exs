defmodule KsefHubWeb.InvoiceLive.ShowTest do
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
        uid: "g-show-1",
        email: "test@example.com",
        name: "Test"
      })

    company = insert(:company)
    insert(:membership, user: user, company: company, role: "owner")

    conn = conn |> log_in_user(user, %{current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  describe "mount" do
    test "renders invoice detail page", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: "income", company: company)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:ok, "<html>preview</html>"} end)

      {:ok, _view, html} = live(conn, ~p"/invoices/#{invoice.id}")
      assert html =~ invoice.invoice_number
      assert html =~ invoice.seller_name
      assert html =~ invoice.buyer_name
    end

    test "renders download dropdown with PDF and XML links", %{conn: conn, company: company} do
      xml = File.read!("test/support/fixtures/sample_income.xml")
      invoice = insert(:invoice, type: "income", xml_content: xml, company: company)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:ok, "<html>preview</html>"} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      assert has_element?(view, "div.dropdown")
      assert has_element?(view, ~s(a[href="/invoices/#{invoice.id}/pdf"]), "PDF")
      assert has_element?(view, ~s(a[href="/invoices/#{invoice.id}/xml"]), "XML")
    end

    test "does not render download dropdown when xml_content is nil", %{
      conn: conn,
      company: company
    } do
      invoice = insert(:invoice, type: "income", xml_content: nil, company: company)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      refute has_element?(view, "div.dropdown")
    end

    test "shows preview when xml_content is available", %{conn: conn, company: company} do
      xml = File.read!("test/support/fixtures/sample_income.xml")
      invoice = insert(:invoice, type: "income", xml_content: xml, company: company)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:ok, "<html>preview</html>"} end)

      {:ok, _view, html} = live(conn, ~p"/invoices/#{invoice.id}")
      assert html =~ "preview"
    end
  end

  describe "approve/reject" do
    test "approve button shown for pending expense invoices", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: "expense", company: company)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")
      assert has_element?(view, "button", "Approve")
      assert has_element?(view, "button", "Reject")
    end

    test "approve button not shown for income invoices", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: "income", company: company)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")
      refute has_element?(view, "button", "Approve")
    end

    test "clicking approve updates status", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: "expense", company: company)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      view |> element("button", "Approve") |> render_click()

      assert has_element?(view, "[class*=rounded-md]", "approved")
      refute has_element?(view, "button", "Approve")
      refute has_element?(view, "button", "Reject")
    end

    test "clicking reject updates status", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: "expense", company: company)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      view |> element("button", "Reject") |> render_click()

      assert has_element?(view, "[class*=rounded-md]", "rejected")
      refute has_element?(view, "button", "Approve")
      refute has_element?(view, "button", "Reject")
    end

    test "approve on income invoice is rejected", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: "income", company: company)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      # Buttons aren't shown for income, but test the server-side guard via hook
      render_hook(view, "approve", %{})

      # Status should remain pending (not changed to approved)
      assert has_element?(view, "[class*=rounded-md]", "pending")
      refute has_element?(view, "[class*=rounded-md]", "approved")
    end

    test "already-approved invoice does not show action buttons", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: "expense", status: "approved", company: company)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      assert has_element?(view, "[class*=rounded-md]", "approved")
      refute has_element?(view, "button", "Approve")
      refute has_element?(view, "button", "Reject")
    end
  end
end
