defmodule KsefHubWeb.InvoiceLive.ShowTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  alias KsefHub.Accounts
  alias KsefHub.Invoices

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.find_or_create_user(%{uid: "g-show-1", email: "test@example.com", name: "Test"})

    conn = conn |> init_test_session(%{user_id: user.id})
    %{conn: conn, user: user}
  end

  describe "mount" do
    test "renders invoice detail page", %{conn: conn} do
      {:ok, invoice} = create_invoice("income")

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml -> {:ok, "<html>preview</html>"} end)

      {:ok, _view, html} = live(conn, ~p"/invoices/#{invoice.id}")
      assert html =~ invoice.invoice_number
      assert html =~ "Seller Co"
      assert html =~ "Buyer Co"
    end

    test "shows preview when xml_content is available", %{conn: conn} do
      xml = File.read!("test/support/fixtures/sample_income.xml")
      {:ok, invoice} = create_invoice("income", xml)

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml -> {:ok, "<html>preview</html>"} end)

      {:ok, _view, html} = live(conn, ~p"/invoices/#{invoice.id}")
      assert html =~ "preview"
    end
  end

  describe "approve/reject" do
    test "approve button shown for pending expense invoices", %{conn: conn} do
      {:ok, invoice} = create_invoice("expense")

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")
      assert has_element?(view, "button", "Approve")
      assert has_element?(view, "button", "Reject")
    end

    test "approve button not shown for income invoices", %{conn: conn} do
      {:ok, invoice} = create_invoice("income")

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")
      refute has_element?(view, "button", "Approve")
    end

    test "clicking approve updates status", %{conn: conn} do
      {:ok, invoice} = create_invoice("expense")

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      view |> element("button", "Approve") |> render_click()

      assert has_element?(view, ".badge", "approved")
      refute has_element?(view, "button", "Approve")
      refute has_element?(view, "button", "Reject")
    end

    test "clicking reject updates status", %{conn: conn} do
      {:ok, invoice} = create_invoice("expense")

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      view |> element("button", "Reject") |> render_click()

      assert has_element?(view, ".badge", "rejected")
      refute has_element?(view, "button", "Approve")
      refute has_element?(view, "button", "Reject")
    end

    test "approve on income invoice is rejected", %{conn: conn} do
      {:ok, invoice} = create_invoice("income")

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      # Buttons aren't shown for income, but test the server-side guard via hook
      render_hook(view, "approve", %{})

      # Status should remain pending (not changed to approved)
      assert has_element?(view, ".badge", "pending")
      refute has_element?(view, ".badge", "approved")
    end

    test "approve on already-approved invoice hides buttons", %{conn: conn} do
      {:ok, invoice} = create_invoice("expense")

      stub(KsefHub.Pdf.Mock, :generate_html, fn _xml -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}")

      view |> element("button", "Approve") |> render_click()
      assert has_element?(view, ".badge", "approved")

      # Approve/Reject buttons should be gone after status change
      refute has_element?(view, "button", "Approve")
      refute has_element?(view, "button", "Reject")
    end
  end

  defp create_invoice(type, xml_content \\ nil) do
    Invoices.create_invoice(%{
      type: type,
      status: "pending",
      seller_nip: "1234567890",
      seller_name: "Seller Co",
      buyer_nip: "0987654321",
      buyer_name: "Buyer Co",
      invoice_number: "FV/#{System.unique_integer([:positive])}",
      issue_date: Date.utc_today(),
      xml_content: xml_content
    })
  end
end
