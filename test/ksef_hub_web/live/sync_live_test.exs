defmodule KsefHubWeb.SyncLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import Phoenix.LiveViewTest

  alias KsefHub.Accounts

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.get_or_create_google_user(%{
        uid: "g-sync-1",
        email: "test@example.com",
        name: "Test"
      })

    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)

    conn = conn |> log_in_user(user, %{current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  describe "mount" do
    test "renders sync page with header and button", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/syncs")
      assert html =~ "Syncs"
      assert html =~ "Sync Now"
    end

    test "shows empty state when no sync jobs", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/syncs")
      assert html =~ "No sync jobs yet"
    end

    test "shows sync jobs in table", %{conn: conn, company: company} do
      insert(:sync_job,
        state: "completed",
        meta: %{"income_count" => 3, "expense_count" => 1},
        args: %{"company_id" => company.id}
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/syncs")
      assert html =~ "completed"
      refute html =~ "No sync jobs yet"
    end
  end

  describe "PubSub" do
    test "refreshes on sync completed event", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/syncs")

      # Insert a job and broadcast
      insert(:sync_job,
        state: "completed",
        meta: %{"income_count" => 2, "expense_count" => 0},
        args: %{"company_id" => company.id}
      )

      send(view.pid, {:sync_completed, %{income: 2, expense: 0}})

      html = render(view)
      assert html =~ "completed"
    end
  end

  describe "trigger_sync" do
    test "clicking Sync Now triggers a manual sync", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/syncs")

      view |> element("button", "Sync Now") |> render_click()

      html = render(view)
      assert html =~ "Manual sync triggered"
    end

    test "disables the button while a sync is already running", %{
      conn: conn,
      company: company
    } do
      insert(:sync_job,
        state: "executing",
        args: %{"company_id" => company.id}
      )

      {:ok, view, html} = live(conn, ~p"/c/#{company.id}/settings/syncs")

      assert html =~ "Syncing…"
      refute html =~ ">\n              Sync Now"
      assert has_element?(view, "button#sync-button[disabled]")
    end

    test "disables the button when another client starts a sync", %{
      conn: conn,
      company: company
    } do
      {:ok, view, html} = live(conn, ~p"/c/#{company.id}/settings/syncs")
      assert html =~ "Sync Now"
      refute has_element?(view, "button#sync-button[disabled]")

      send(view.pid, {:sync_running_changed, true})

      html = render(view)
      assert html =~ "Syncing…"
      assert has_element?(view, "button#sync-button[disabled]")

      send(view.pid, {:sync_running_changed, false})

      html = render(view)
      assert html =~ "Sync Now"
      refute html =~ "Syncing…"
      refute has_element?(view, "button#sync-button[disabled]")
    end
  end
end
