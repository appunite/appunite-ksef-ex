defmodule KsefHubWeb.RoleBasedNavTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import Phoenix.LiveViewTest

  describe "role-based navigation visibility" do
    test "owner sees Certificates and API Tokens nav items", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      {:ok, view, _html} =
        conn
        |> log_in_user(user, %{current_company_id: company.id})
        |> live("/c/#{company.id}/dashboard")

      assert has_element?(view, "a[href='/c/#{company.id}/dashboard']")
      assert has_element?(view, "a[href='/c/#{company.id}/invoices']")
      # Categories, Tags, Certificates, API Tokens are now under Settings
      assert has_element?(view, "a[href='/c/#{company.id}/settings']")
    end

    test "accountant does not see admin-only nav items", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :accountant)

      {:ok, view, _html} =
        conn
        |> log_in_user(user, %{current_company_id: company.id})
        |> live("/c/#{company.id}/dashboard")

      assert has_element?(view, "a[href='/c/#{company.id}/dashboard']")
      assert has_element?(view, "a[href='/c/#{company.id}/invoices']")
      # Settings is visible to all roles (General tab has no permission requirement)
      assert has_element?(view, "a[href='/c/#{company.id}/settings']")
    end

    test "reviewer does not see admin-only nav items", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :reviewer)

      {:ok, view, _html} =
        conn
        |> log_in_user(user, %{current_company_id: company.id})
        |> live("/c/#{company.id}/dashboard")

      assert has_element?(view, "a[href='/c/#{company.id}/dashboard']")
      assert has_element?(view, "a[href='/c/#{company.id}/invoices']")
      assert has_element?(view, "a[href='/c/#{company.id}/settings']")
    end
  end
end
