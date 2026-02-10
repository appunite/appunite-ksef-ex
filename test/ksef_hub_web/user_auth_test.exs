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

    test "redirects to signed_in_path", %{conn: conn, user: user} do
      conn = UserAuth.log_in_user(conn, user)
      assert redirected_to(conn) =~ "/"
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
