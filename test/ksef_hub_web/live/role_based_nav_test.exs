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
      assert has_element?(view, "a[href='/c/#{company.id}/categories']")
      assert has_element?(view, "a[href='/c/#{company.id}/tags']")
      assert has_element?(view, "a[href='/c/#{company.id}/certificates']")
      assert has_element?(view, "a[href='/c/#{company.id}/tokens']")
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
      refute has_element?(view, "a[href='/c/#{company.id}/categories']")
      refute has_element?(view, "a[href='/c/#{company.id}/tags']")
      refute has_element?(view, "a[href='/c/#{company.id}/certificates']")
      # Accountant can manage tokens
      assert has_element?(view, "a[href='/c/#{company.id}/tokens']")
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
      refute has_element?(view, "a[href='/c/#{company.id}/categories']")
      refute has_element?(view, "a[href='/c/#{company.id}/tags']")
      refute has_element?(view, "a[href='/c/#{company.id}/certificates']")
      refute has_element?(view, "a[href='/c/#{company.id}/tokens']")
    end
  end
end
