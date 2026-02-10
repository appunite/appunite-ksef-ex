defmodule KsefHubWeb.UserRegistrationLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  describe "Registration page" do
    test "renders registration form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/users/register")

      assert html =~ "Create an account"
      assert html =~ "Log in"
      assert html =~ "Sign in with Google"
    end

    test "redirects if already logged in", %{conn: conn} do
      user = insert(:password_user)
      conn = log_in_user(conn, user)

      assert {:error, redirect} = live(conn, ~p"/users/register")
      assert {:redirect, %{to: "/dashboard"}} = redirect
    end
  end

  describe "register user" do
    test "creates account and redirects", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/register")

      email = "test_register#{System.unique_integer([:positive])}@example.com"

      form =
        form(view, "#registration_form", user: %{email: email, password: "valid_password123"})

      render_submit(form)

      conn = follow_trigger_action(form, conn)
      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "renders errors for invalid data on submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/register")

      result =
        view
        |> form("#registration_form", user: %{email: "short", password: "short"})
        |> render_submit()

      assert result =~ "Create an account"
    end

    test "renders errors for duplicate email", %{conn: conn} do
      user = insert(:password_user)
      {:ok, view, _html} = live(conn, ~p"/users/register")

      result =
        view
        |> form("#registration_form", user: %{email: user.email, password: "valid_password123"})
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end
end
