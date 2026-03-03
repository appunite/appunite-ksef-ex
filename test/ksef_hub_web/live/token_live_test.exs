defmodule KsefHubWeb.TokenLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  alias KsefHub.Accounts

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.get_or_create_google_user(%{
        uid: "g-tok-1",
        email: "test@example.com",
        name: "Test"
      })

    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)

    conn = conn |> log_in_user(user, %{current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  describe "mount" do
    test "renders token page with company-scoped tokens", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/tokens")
      assert html =~ "API Tokens"
      assert html =~ "New Token"
    end

    test "shows empty state when no tokens for company", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/tokens")
      assert html =~ "No API tokens yet"
    end

    test "shows only tokens for current company", %{conn: conn, user: user, company: company} do
      {:ok, %{api_token: visible_token}} =
        Accounts.create_api_token(user.id, company.id, %{name: "This Company Token"})

      other_company = insert(:company)
      insert(:membership, user: user, company: other_company, role: :owner)

      {:ok, %{api_token: hidden_token}} =
        Accounts.create_api_token(user.id, other_company.id, %{name: "Other Company Token"})

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tokens")

      assert has_element?(
               view,
               "[data-testid='token-name-#{visible_token.id}']",
               "This Company Token"
             )

      refute has_element?(view, "[data-testid='token-name-#{hidden_token.id}']")
    end
  end

  describe "access control" do
    test "non-owner is redirected away", %{company: company} do
      {:ok, non_owner} =
        Accounts.get_or_create_google_user(%{
          uid: "g-tok-nonowner",
          email: "nonowner@example.com",
          name: "Non-Owner"
        })

      insert(:membership, user: non_owner, company: company, role: :accountant)

      conn =
        build_conn()
        |> log_in_user(non_owner, %{current_company_id: company.id})

      expected_path = "/c/#{company.id}/invoices"

      assert {:error, {:redirect, %{to: ^expected_path, flash: %{"error" => message}}}} =
               live(conn, ~p"/c/#{company.id}/tokens")

      assert message =~ "Only company owners"
    end
  end

  describe "create token" do
    test "toggle form shows create form", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tokens")

      view |> element("button", "New Token") |> render_click()
      assert has_element?(view, "button", "Create Token")
    end

    test "creates token scoped to current company", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tokens")

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
    test "revokes a token scoped to current company", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, _} =
        Accounts.create_api_token(user.id, company.id, %{name: "Revoke Test"})

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tokens")

      view |> element("button", "Revoke") |> render_click()

      html = render(view)
      assert html =~ "Revoked"
    end
  end

  describe "dismiss token" do
    test "dismisses the plaintext token alert", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tokens")

      view |> element("button", "New Token") |> render_click()

      view
      |> element("form[phx-submit=create]")
      |> render_submit(%{token: %{name: "Dismiss Test", description: ""}})

      assert render(view) =~ "Copy your API token now"

      view |> element("button", "Dismiss") |> render_click()
      refute render(view) =~ "Copy your API token now"
    end
  end
end
