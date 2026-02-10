defmodule KsefHubWeb.RoleBasedNavTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import Phoenix.LiveViewTest

  describe "role-based navigation visibility" do
    test "owner sees Certificates and API Tokens nav items", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: "owner")

      {:ok, view, _html} =
        conn
        |> init_test_session(%{user_id: user.id, current_company_id: company.id})
        |> live("/dashboard")

      assert has_element?(view, "a[href='/dashboard']")
      assert has_element?(view, "a[href='/invoices']")
      assert has_element?(view, "a[href='/certificates']")
      assert has_element?(view, "a[href='/tokens']")
    end

    test "accountant does not see Certificates or API Tokens nav items", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: "accountant")

      {:ok, view, _html} =
        conn
        |> init_test_session(%{user_id: user.id, current_company_id: company.id})
        |> live("/dashboard")

      assert has_element?(view, "a[href='/dashboard']")
      assert has_element?(view, "a[href='/invoices']")
      refute has_element?(view, "a[href='/certificates']")
      refute has_element?(view, "a[href='/tokens']")
    end

    test "invoice_reviewer does not see Certificates or API Tokens nav items", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: "invoice_reviewer")

      {:ok, view, _html} =
        conn
        |> init_test_session(%{user_id: user.id, current_company_id: company.id})
        |> live("/dashboard")

      assert has_element?(view, "a[href='/dashboard']")
      assert has_element?(view, "a[href='/invoices']")
      refute has_element?(view, "a[href='/certificates']")
      refute has_element?(view, "a[href='/tokens']")
    end
  end
end
