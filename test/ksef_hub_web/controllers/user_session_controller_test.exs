defmodule KsefHubWeb.UserSessionControllerTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory

  setup do
    password = "valid_password123"
    user = insert(:password_user, hashed_password: Bcrypt.hash_pwd_salt(password))
    %{user: user, password: password}
  end

  describe "POST /users/log-in" do
    test "logs in with valid credentials", %{conn: conn, user: user, password: password} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => password}
        })

      assert redirected_to(conn) == ~p"/companies"
      assert get_session(conn, :user_token)
    end

    test "redirects to login with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => "wrong_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password."
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
      refute get_session(conn, :user_token)
    end
  end
end
