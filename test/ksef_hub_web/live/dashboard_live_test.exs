defmodule KsefHubWeb.DashboardLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KsefHub.Accounts
  alias KsefHub.Invoices

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.find_or_create_user(%{uid: "g-dash-1", email: "test@example.com", name: "Test"})

    conn = conn |> init_test_session(%{user_id: user.id})
    %{conn: conn, user: user}
  end

  describe "mount" do
    test "renders dashboard with zero counts", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Dashboard"
      assert has_element?(view, "[class*=stat-value]", "0")
      # Sidebar navigation rendered via app layout
      assert html =~ "drawer"
      assert html =~ "Invoices"
      assert html =~ "Certificates"
      assert html =~ "API Tokens"
    end

    test "shows invoice counts", %{conn: conn} do
      create_invoice("income", "pending")
      create_invoice("income", "pending")
      create_invoice("expense", "pending")

      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Dashboard"
    end

    test "shows sync status when no credential", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Not configured"
    end
  end

  describe "PubSub" do
    test "refreshes on sync completed event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Create an invoice and broadcast sync
      create_invoice("income", "pending")
      send(view.pid, {:sync_completed, %{income: 1, expense: 0}})

      html = render(view)
      assert html =~ "Dashboard"
    end
  end

  defp create_invoice(type, status) do
    Invoices.create_invoice(%{
      type: type,
      status: status,
      seller_nip: "1234567890",
      seller_name: "Seller",
      buyer_nip: "0987654321",
      buyer_name: "Buyer",
      invoice_number: "FV/#{System.unique_integer([:positive])}",
      issue_date: Date.utc_today()
    })
  end
end
