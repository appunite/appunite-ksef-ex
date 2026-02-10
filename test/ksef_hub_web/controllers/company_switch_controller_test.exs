defmodule KsefHubWeb.CompanySwitchControllerTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory

  describe "update/2" do
    test "user with membership can switch company", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: "owner")

      conn =
        conn
        |> init_test_session(%{user_id: user.id})
        |> post(~p"/switch-company/#{company.id}")

      assert redirected_to(conn) == "/dashboard"
      assert get_session(conn, :current_company_id) == company.id
    end

    test "user without membership cannot switch to that company", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)

      conn =
        conn
        |> init_test_session(%{user_id: user.id})
        |> post(~p"/switch-company/#{company.id}")

      assert redirected_to(conn) == "/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Company not found."
      refute get_session(conn, :current_company_id) == company.id
    end

    test "non-existent company returns error flash", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> init_test_session(%{user_id: user.id})
        |> post(~p"/switch-company/#{Ecto.UUID.generate()}")

      assert redirected_to(conn) == "/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Company not found."
    end

    test "respects return_to parameter", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: "accountant")

      conn =
        conn
        |> init_test_session(%{user_id: user.id})
        |> post(~p"/switch-company/#{company.id}", %{return_to: "/invoices"})

      assert redirected_to(conn) == "/invoices"
    end
  end
end
