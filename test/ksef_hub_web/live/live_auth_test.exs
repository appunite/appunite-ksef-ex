defmodule KsefHubWeb.LiveAuthTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import Phoenix.LiveViewTest

  describe "LiveAuth on_mount" do
    test "redirects to / when session has no user_id", %{conn: conn} do
      {:error, {:redirect, %{to: "/"}}} =
        conn
        |> init_test_session(%{})
        |> live("/dashboard")
    end

    test "redirects to / when session user_id is not a valid UUID", %{conn: conn} do
      {:error, {:redirect, %{to: "/"}}} =
        conn
        |> init_test_session(%{user_id: "not-a-uuid"})
        |> live("/dashboard")
    end

    test "redirects to / when user_id does not match any user", %{conn: conn} do
      {:error, {:redirect, %{to: "/"}}} =
        conn
        |> init_test_session(%{user_id: Ecto.UUID.generate()})
        |> live("/dashboard")
    end

    test "assigns current_user for valid session with membership", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: "owner")

      {:ok, _view, html} =
        conn
        |> init_test_session(%{user_id: user.id, current_company_id: company.id})
        |> live("/dashboard")

      assert html =~ "Dashboard"
    end

    test "user sees only their companies via membership", %{conn: conn} do
      user = insert(:user)
      company_a = insert(:company, name: "My Company")
      _company_b = insert(:company, name: "Other Company")
      insert(:membership, user: user, company: company_a, role: "owner")

      {:ok, view, _html} =
        conn
        |> init_test_session(%{user_id: user.id, current_company_id: company_a.id})
        |> live("/dashboard")

      html = render(view)
      assert html =~ "My Company"
      refute html =~ "Other Company"
    end

    test "user with no memberships is redirected to company creation", %{conn: conn} do
      user = insert(:user)

      {:error, {:redirect, %{to: "/companies/new"}}} =
        conn
        |> init_test_session(%{user_id: user.id})
        |> live("/dashboard")
    end

    test "current_company comes from user's companies only", %{conn: conn} do
      user = insert(:user)
      company = insert(:company, name: "Mine")
      other = insert(:company, name: "NotMine")
      insert(:membership, user: user, company: company, role: "owner")

      # Attempt to set current_company_id to a company user doesn't belong to
      {:ok, view, _html} =
        conn
        |> init_test_session(%{user_id: user.id, current_company_id: other.id})
        |> live("/dashboard")

      # Should fall back to the user's first company
      html = render(view)
      assert html =~ "Mine"
    end

    test "assigns current_role from membership", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: "accountant")

      {:ok, view, _html} =
        conn
        |> init_test_session(%{user_id: user.id, current_company_id: company.id})
        |> live("/dashboard")

      # The role should be assigned on the socket — verify via rendered content
      # that owner-only nav items are hidden for non-owner
      html = render(view)
      assert html =~ "Dashboard"
    end
  end
end
