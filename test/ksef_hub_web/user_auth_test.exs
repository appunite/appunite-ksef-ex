defmodule KsefHubWeb.UserAuthTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHubWeb.UserAuth

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, KsefHubWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{conn: conn, user: insert(:user)}
  end

  describe "log_in_user/3" do
    test "stores user token in session", %{conn: conn, user: user} do
      conn = UserAuth.log_in_user(conn, user)

      assert token = get_session(conn, :user_token)
      assert redirected_to(conn) =~ "/"
      assert Accounts.get_user_by_session_token(token)
    end

    test "clears everything previously stored in session", %{conn: conn, user: user} do
      conn = conn |> put_session(:foo, "bar") |> UserAuth.log_in_user(user)
      refute get_session(conn, :foo)
    end

    test "redirects to /companies when user has no companies", %{conn: conn, user: user} do
      conn = UserAuth.log_in_user(conn, user)
      assert redirected_to(conn) == "/companies"
    end

    test "redirects to company-scoped invoices when user has a company", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      conn = UserAuth.log_in_user(conn, user)
      assert redirected_to(conn) == "/c/#{company.id}/invoices"
    end

    test "respects valid return_to path", %{conn: conn, user: user} do
      conn = UserAuth.log_in_user(conn, user, %{return_to: "/invitations/accept/abc123"})
      assert redirected_to(conn) == "/invitations/accept/abc123"
    end

    test "ignores return_to with absolute URL (open-redirect)", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      conn = UserAuth.log_in_user(conn, user, %{return_to: "https://evil.com"})
      assert redirected_to(conn) == "/c/#{company.id}/invoices"
    end

    test "ignores return_to with protocol-relative URL (open-redirect)", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      conn = UserAuth.log_in_user(conn, user, %{return_to: "//evil.com"})
      assert redirected_to(conn) == "/c/#{company.id}/invoices"
    end

    test "ignores return_to that does not start with /", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      conn = UserAuth.log_in_user(conn, user, %{return_to: "evil.com/path"})
      assert redirected_to(conn) == "/c/#{company.id}/invoices"
    end

    test "ignores empty return_to", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      conn = UserAuth.log_in_user(conn, user, %{return_to: ""})
      assert redirected_to(conn) == "/c/#{company.id}/invoices"
    end
  end

  describe "log_out_user/1" do
    test "deletes token from database and session", %{conn: conn, user: user} do
      token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, token)
        |> UserAuth.log_out_user()

      refute get_session(conn, :user_token)
      refute Accounts.get_user_by_session_token(token)
      assert redirected_to(conn) == "/"
    end

    test "works even if no session token", %{conn: conn} do
      conn = UserAuth.log_out_user(conn)
      refute get_session(conn, :user_token)
      assert redirected_to(conn) == "/"
    end
  end
end
