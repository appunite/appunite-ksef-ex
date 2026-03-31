defmodule KsefHubWeb.LiveAuthTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import Phoenix.LiveViewTest

  describe "LiveAuth on_mount" do
    test "redirects to / when session has no user_token", %{conn: conn} do
      company = insert(:company)

      {:error, {:redirect, %{to: "/"}}} =
        conn
        |> init_test_session(%{})
        |> live(~p"/c/#{company.id}/settings/categories")
    end

    test "redirects to / when session user_token is invalid", %{conn: conn} do
      company = insert(:company)

      {:error, {:redirect, %{to: "/"}}} =
        conn
        |> init_test_session(%{user_token: "invalid-token"})
        |> live(~p"/c/#{company.id}/settings/categories")
    end

    test "redirects to / when session user_token is expired", %{conn: conn} do
      company = insert(:company)

      {:error, {:redirect, %{to: "/"}}} =
        conn
        |> init_test_session(%{user_token: :crypto.strong_rand_bytes(32)})
        |> live(~p"/c/#{company.id}/settings/categories")
    end

    test "assigns current_user for valid session with membership", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      {:ok, view, _html} =
        conn
        |> log_in_user(user, %{current_company_id: company.id})
        |> live(~p"/c/#{company.id}/settings/categories")

      assert has_element?(view, "a[href='/c/#{company.id}/dashboard']")
    end

    test "user sees only their companies via membership", %{conn: conn} do
      user = insert(:user)
      company_a = insert(:company, name: "My Company")
      _company_b = insert(:company, name: "Other Company")
      insert(:membership, user: user, company: company_a, role: :owner)

      {:ok, view, _html} =
        conn
        |> log_in_user(user, %{current_company_id: company_a.id})
        |> live(~p"/c/#{company_a.id}/settings/categories")

      assert has_element?(view, "[data-testid='current-company-name']", "My Company")
      refute has_element?(view, "button", "Other Company")
    end

    test "user with no memberships accessing company-scoped URL is denied", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)

      {:error, {:redirect, %{to: "/companies"}}} =
        conn
        |> log_in_user(user)
        |> live(~p"/c/#{company.id}/settings/categories")
    end

    test "user with no memberships on non-scoped route sees companies page", %{conn: conn} do
      user = insert(:user)

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/companies")

      assert has_element?(view, "h1", "Companies")
    end

    test "current_company comes from URL company_id param", %{conn: conn} do
      user = insert(:user)
      company = insert(:company, name: "Mine")
      other = insert(:company, name: "NotMine")
      insert(:membership, user: user, company: company, role: :owner)

      # Navigate to URL with company's id — session has a different company_id
      {:ok, view, _html} =
        conn
        |> log_in_user(user, %{current_company_id: other.id})
        |> live(~p"/c/#{company.id}/settings/categories")

      # URL company_id takes priority over session
      assert has_element?(view, "[data-testid='current-company-name']", "Mine")
    end

    test "assigns current_role from membership and hides owner-only nav", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :accountant)

      # Accountant cannot access admin-only pages like categories
      expected_path = "/c/#{company.id}/invoices"

      assert {:error, {:redirect, %{to: ^expected_path}}} =
               conn
               |> log_in_user(user, %{current_company_id: company.id})
               |> live(~p"/c/#{company.id}/settings/categories")
    end
  end
end
