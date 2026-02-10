defmodule KsefHubWeb.TokenLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import KsefHub.Factory

  alias KsefHub.Accounts

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.find_or_create_user(%{uid: "g-tok-1", email: "test@example.com", name: "Test"})

    company = insert(:company)
    insert(:membership, user: user, company: company, role: "owner")

    conn = conn |> init_test_session(%{user_id: user.id, current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  describe "mount" do
    test "renders token page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/tokens")
      assert html =~ "API Tokens"
      assert html =~ "New Token"
    end

    test "shows empty state when no tokens", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/tokens")
      assert html =~ "No API tokens yet"
    end
  end

  describe "create token" do
    test "toggle form shows create form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tokens")

      view |> element("button", "New Token") |> render_click()
      assert has_element?(view, "button", "Create Token")
    end

    test "creates token and shows plaintext", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tokens")

      view |> element("button", "New Token") |> render_click()

      view
      |> element("form[phx-submit=create]")
      |> render_submit(%{token: %{name: "My Token", description: "For testing"}})

      html = render(view)
      assert html =~ "Copy your API token now"
      assert html =~ "My Token"
    end
  end

  describe "revoke token" do
    test "revokes a token", %{conn: conn, user: user} do
      {:ok, %{api_token: _token}} =
        Accounts.create_api_token(user.id, %{name: "Revoke Test"})

      {:ok, view, _html} = live(conn, ~p"/tokens")

      view |> element("button", "Revoke") |> render_click()

      html = render(view)
      assert html =~ "Revoked"
    end
  end

  describe "dismiss token" do
    test "dismisses the plaintext token alert", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tokens")

      # Create a token first
      view |> element("button", "New Token") |> render_click()

      view
      |> element("form[phx-submit=create]")
      |> render_submit(%{token: %{name: "Dismiss Test", description: ""}})

      # Token should be visible
      assert render(view) =~ "Copy your API token now"

      # Dismiss it
      view |> element("button", "Dismiss") |> render_click()
      refute render(view) =~ "Copy your API token now"
    end
  end
end
