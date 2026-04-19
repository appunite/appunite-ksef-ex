defmodule KsefHubWeb.SettingsLive.GeneralTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  setup %{conn: conn} do
    user = insert(:user)
    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)

    conn = log_in_user(conn, user, %{current_company_id: company.id})
    %{conn: conn, company: company, user: user}
  end

  describe "General settings page" do
    test "renders with theme toggle", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings")

      assert html =~ "General"
      assert html =~ "Theme"
      assert html =~ "phx:set-theme"
    end

    test "shows settings sidebar with all tabs for owner", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings")

      assert has_element?(view, "nav[aria-label='Settings']")

      for tab <- ~w(General Exports Syncs Categories Team Certificates) ++ ["API Tokens"] do
        assert has_element?(view, "nav[aria-label='Settings'] a", tab)
      end
    end
  end

  describe "settings sidebar tab visibility" do
    test "reviewer sees General, Syncs, API Tokens, and Payment-related tabs", %{
      conn: conn,
      company: company
    } do
      reviewer = insert(:user)
      insert(:membership, user: reviewer, company: company, role: :approver)
      conn = log_in_user(conn, reviewer, %{current_company_id: company.id})

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings")

      assert has_element?(view, "nav[aria-label='Settings'] a", "General")
      assert has_element?(view, "nav[aria-label='Settings'] a", "Syncs")
      assert has_element?(view, "nav[aria-label='Settings'] a", "API Tokens")
      refute has_element?(view, "nav[aria-label='Settings'] a", "Certificates")
      refute has_element?(view, "nav[aria-label='Settings'] a", "Categories")

      refute has_element?(view, "nav[aria-label='Settings'] a", "Team")
      refute has_element?(view, "nav[aria-label='Settings'] a", "Exports")
    end

    test "accountant sees General, Exports, API Tokens tabs", %{conn: conn, company: company} do
      accountant = insert(:user)
      insert(:membership, user: accountant, company: company, role: :accountant)
      conn = log_in_user(conn, accountant, %{current_company_id: company.id})

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings")

      assert has_element?(view, "nav[aria-label='Settings'] a", "General")
      assert has_element?(view, "nav[aria-label='Settings'] a", "Exports")
      assert has_element?(view, "nav[aria-label='Settings'] a", "API Tokens")
      refute has_element?(view, "nav[aria-label='Settings'] a", "Certificates")
      refute has_element?(view, "nav[aria-label='Settings'] a", "Categories")

      refute has_element?(view, "nav[aria-label='Settings'] a", "Team")
      refute has_element?(view, "nav[aria-label='Settings'] a", "Syncs")
    end
  end
end
