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

      {:ok, view, _html} = live(conn, ~p"/users/confirm/#{token}")
      assert has_element?(view, "[data-testid='page-title']", "Confirm Account")
    end

    test "confirms the user account", %{conn: conn, user: user} do
      {token, _} =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      {:ok, view, _html} = live(conn, ~p"/users/confirm/#{token}")

      view
      |> form("#confirmation_form")
      |> render_submit()

      assert has_element?(view, "[data-testid='confirmation-success']")
      assert Accounts.get_user!(user.id).confirmed_at
    end

    test "does not confirm with invalid token", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/confirm/invalid-token")

      view
      |> form("#confirmation_form")
      |> render_submit()

      refute has_element?(view, "[data-testid='confirmation-success']")
    end
  end
end
