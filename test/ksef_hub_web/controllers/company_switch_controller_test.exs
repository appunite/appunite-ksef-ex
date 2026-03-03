defmodule KsefHubWeb.CompanySwitchControllerTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory

  describe "update/2" do
    test "user with membership can switch company", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/switch-company/#{company.id}")

      assert redirected_to(conn) == "/c/#{company.id}/invoices"
      assert get_session(conn, :current_company_id) == company.id
    end

    test "user without membership cannot switch to that company", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/switch-company/#{company.id}")

      assert redirected_to(conn) == "/companies"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Company not found."
      assert is_nil(get_session(conn, :current_company_id))
    end

    test "non-existent company returns error flash", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/switch-company/#{Ecto.UUID.generate()}")

      assert redirected_to(conn) == "/companies"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Company not found."
      assert is_nil(get_session(conn, :current_company_id))
    end

    test "respects return_to parameter with company-scoped path", %{conn: conn} do
      user = insert(:user)
      old_company = insert(:company)
      new_company = insert(:company)
      insert(:membership, user: user, company: old_company, role: :accountant)
      insert(:membership, user: user, company: new_company, role: :accountant)

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/switch-company/#{new_company.id}", %{
          return_to: "/c/#{old_company.id}/invoices"
        })

      # The company_id in the path is rewritten to the new company
      assert redirected_to(conn) == "/c/#{new_company.id}/invoices"
    end

    test "rejects external URL in return_to (open redirect protection)", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/switch-company/#{company.id}", %{return_to: "https://evil.com"})

      assert redirected_to(conn) == "/c/#{company.id}/invoices"
    end

    test "rejects protocol-relative URL in return_to", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/switch-company/#{company.id}", %{return_to: "//evil.com"})

      assert redirected_to(conn) == "/c/#{company.id}/invoices"
    end
  end
end
