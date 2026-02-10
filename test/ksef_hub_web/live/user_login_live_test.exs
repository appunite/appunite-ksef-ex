defmodule KsefHubWeb.UserLoginLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  describe "Log in page" do
    test "renders log in form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Log in"
      assert html =~ "Forgot your password?"
      assert html =~ "Sign up"
      assert html =~ "Sign in with Google"
    end

    test "redirects if already logged in", %{conn: conn} do
      user = insert(:password_user)
      conn = log_in_user(conn, user)

      assert {:error, redirect} = live(conn, ~p"/users/log-in")
      assert {:redirect, %{to: "/dashboard"}} = redirect
    end
  end

  describe "user login" do
    test "redirects on valid credentials via session controller", %{conn: conn} do
      password = "valid_password123"
      user = insert(:password_user, hashed_password: Bcrypt.hash_pwd_salt(password))

      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      # The login form uses phx-update="ignore" and POSTs directly via
      # phx-trigger-action. We test the form renders, then test the POST
      # through the session controller.
      assert has_element?(view, "#login_form")

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => password}
        })

      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "shows error on invalid credentials via session controller", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => "wrong@example.com", "password" => "wrong_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password."
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end
end
