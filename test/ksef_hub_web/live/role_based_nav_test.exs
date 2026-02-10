defmodule KsefHubWeb.RoleBasedNavTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import Phoenix.LiveViewTest

  describe "role-based navigation visibility" do
    test "owner sees Certificates and API Tokens nav items", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: "owner")

      {:ok, _view, html} =
        conn
        |> init_test_session(%{user_id: user.id, current_company_id: company.id})
        |> live("/dashboard")

      assert html =~ "Certificates"
      assert html =~ "API Tokens"
    end

    test "accountant does not see Certificates or API Tokens nav items", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: "accountant")

      {:ok, _view, html} =
        conn
        |> init_test_session(%{user_id: user.id, current_company_id: company.id})
        |> live("/dashboard")

      refute html =~ "Certificates"
      refute html =~ "API Tokens"
      assert html =~ "Dashboard"
      assert html =~ "Invoices"
    end

    test "invoice_reviewer does not see Certificates or API Tokens nav items", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: "invoice_reviewer")

      {:ok, _view, html} =
        conn
        |> init_test_session(%{user_id: user.id, current_company_id: company.id})
        |> live("/dashboard")

      refute html =~ "Certificates"
      refute html =~ "API Tokens"
      assert html =~ "Dashboard"
      assert html =~ "Invoices"
    end
  end
end
