defmodule KsefHubWeb.UserConfirmationLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  alias KsefHub.Accounts

  setup do
    user = insert(:password_user, confirmed_at: nil)
    %{user: user}
  end

  describe "Confirm user" do
    test "renders confirmation page", %{conn: conn, user: user} do
      {token, _} =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      {:ok, _view, html} = live(conn, ~p"/users/confirm/#{token}")
      assert html =~ "Confirm Account"
    end

    test "confirms the user account", %{conn: conn, user: user} do
      {token, _} =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      {:ok, view, _html} = live(conn, ~p"/users/confirm/#{token}")

      result =
        view
        |> form("#confirmation_form")
        |> render_submit()

      assert result =~ "Your account has been confirmed"

      assert Accounts.get_user!(user.id).confirmed_at
    end

    test "does not confirm with invalid token", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/confirm/invalid-token")

      result =
        view
        |> form("#confirmation_form")
        |> render_submit()

      assert result =~ "Confirmation link is invalid or it has expired"
    end
  end
end
