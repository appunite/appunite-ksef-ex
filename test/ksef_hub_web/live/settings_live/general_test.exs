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

    test "shows settings sidebar with tabs", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings")

      assert has_element?(view, "nav[aria-label='Settings']")
      assert has_element?(view, "a", "General")
      assert has_element?(view, "a", "Certificates")
      assert has_element?(view, "a", "API Tokens")
      assert has_element?(view, "a", "Categories")
      assert has_element?(view, "a", "Tags")
      assert has_element?(view, "a", "Team")
    end
  end

  describe "settings sidebar tab visibility" do
    test "owner sees all tabs", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings")

      assert has_element?(view, "a", "General")
      assert has_element?(view, "a", "Certificates")
      assert has_element?(view, "a", "API Tokens")
      assert has_element?(view, "a", "Categories")
      assert has_element?(view, "a", "Tags")
      assert has_element?(view, "a", "Team")
    end

    test "reviewer sees only General and API Tokens tabs", %{conn: conn, company: company} do
      reviewer = insert(:user)
      insert(:membership, user: reviewer, company: company, role: :reviewer)
      conn = log_in_user(conn, reviewer, %{current_company_id: company.id})

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings")

      assert has_element?(view, "a", "General")
      assert has_element?(view, "a", "API Tokens")
      refute has_element?(view, "nav[aria-label='Settings'] a", "Certificates")
      refute has_element?(view, "nav[aria-label='Settings'] a", "Categories")
      refute has_element?(view, "nav[aria-label='Settings'] a", "Tags")
      refute has_element?(view, "nav[aria-label='Settings'] a", "Team")
    end

    test "accountant sees General and API Tokens tabs", %{conn: conn, company: company} do
      accountant = insert(:user)
      insert(:membership, user: accountant, company: company, role: :accountant)
      conn = log_in_user(conn, accountant, %{current_company_id: company.id})

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings")

      assert has_element?(view, "a", "General")
      assert has_element?(view, "a", "API Tokens")
      refute has_element?(view, "nav[aria-label='Settings'] a", "Certificates")
      refute has_element?(view, "nav[aria-label='Settings'] a", "Categories")
      refute has_element?(view, "nav[aria-label='Settings'] a", "Tags")
      refute has_element?(view, "nav[aria-label='Settings'] a", "Team")
    end
  end
end
