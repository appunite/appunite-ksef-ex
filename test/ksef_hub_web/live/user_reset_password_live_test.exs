defmodule KsefHubWeb.UserResetPasswordLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  alias KsefHub.Accounts

  setup do
    user = insert(:password_user)

    {token, _} =
      extract_user_token(fn url ->
        Accounts.deliver_user_reset_password_instructions(user, url)
      end)

    %{user: user, token: token}
  end

  describe "Reset password page" do
    test "renders the reset password page", %{conn: conn, token: token} do
      {:ok, view, _html} = live(conn, ~p"/users/reset-password/#{token}")

      assert has_element?(view, "[data-testid='page-title']", "Reset Password")
    end

    test "redirects with invalid token", %{conn: conn} do
      {:error, {:redirect, %{to: "/", flash: flash}}} =
        live(conn, ~p"/users/reset-password/invalid-token")

      assert flash["error"] =~ "Reset password link is invalid"
    end
  end

  describe "Reset password" do
    test "resets password", %{conn: conn, token: token} do
      {:ok, view, _html} = live(conn, ~p"/users/reset-password/#{token}")

      {:ok, conn} =
        view
        |> form("#reset_password_form",
          user: %{password: "new_valid_password123"}
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Password reset successfully"
    end

    test "renders errors for invalid password", %{conn: conn, token: token} do
      {:ok, view, _html} = live(conn, ~p"/users/reset-password/#{token}")

      result =
        view
        |> form("#reset_password_form", user: %{password: "short"})
        |> render_submit()

      assert result =~ "should be at least 12 character"
    end
  end
end
