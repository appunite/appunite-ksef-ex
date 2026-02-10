defmodule KsefHubWeb.UserForgotPasswordLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  describe "Forgot password page" do
    test "renders the forgot password page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/users/reset-password")

      assert html =~ "Forgot your password?"
      assert html =~ "Register"
      assert html =~ "Log in"
    end

    test "sends reset password email and redirects", %{conn: conn} do
      user = insert(:password_user)

      {:ok, view, _html} = live(conn, ~p"/users/reset-password")

      {:ok, conn} =
        view
        |> form("#reset_password_form", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"
    end

    test "does not reveal if email is not in system", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/reset-password")

      {:ok, conn} =
        view
        |> form("#reset_password_form", user: %{email: "nobody@example.com"})
        |> render_submit()
        |> follow_redirect(conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"
    end
  end
end
