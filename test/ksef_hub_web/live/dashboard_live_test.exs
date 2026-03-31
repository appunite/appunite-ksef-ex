defmodule KsefHubWeb.DashboardLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import KsefHub.Factory

  alias KsefHub.Accounts

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.get_or_create_google_user(%{
        uid: "g-dash-1",
        email: "test@example.com",
        name: "Test"
      })

    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)

    conn = conn |> log_in_user(user, %{current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  describe "mount" do
    test "renders dashboard with zero counts", %{conn: conn, company: company} do
      {:ok, view, html} = live(conn, ~p"/c/#{company.id}/dashboard")
      assert html =~ "Dashboard"
      assert has_element?(view, "[class*='text-2xl font-bold']", "0")
      # Top navbar navigation rendered via app layout
      assert html =~ "border-b border-border"
      assert html =~ "Invoices"
      assert html =~ "Settings"
    end

    test "shows invoice counts", %{conn: conn, company: company} do
      insert(:invoice, type: :income, status: :pending, company: company)
      insert(:invoice, type: :income, status: :pending, company: company)
      insert(:invoice, type: :expense, status: :pending, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/dashboard")
      assert has_element?(view, "[class*='text-2xl font-bold']", "3")
      assert has_element?(view, "[class*='text-2xl font-bold']", "2")
      assert has_element?(view, "[class*='text-2xl font-bold']", "1")
    end

    test "shows sync status when no credential", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/dashboard")
      assert html =~ "Not configured"
    end
  end

  describe "PubSub" do
    test "refreshes on sync completed event", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/dashboard")

      # Verify zero counts initially
      assert has_element?(view, "[class*='text-2xl font-bold']", "0")

      # Create an invoice and broadcast sync
      insert(:invoice, type: :income, status: :pending, company: company)
      send(view.pid, {:sync_completed, %{income: 1, expense: 0}})

      # Counts should update after sync event
      assert has_element?(view, "[class*='text-2xl font-bold']", "1")
    end
  end
end
