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
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/tokens")
      assert html =~ "API Tokens"
      assert html =~ "New Token"
    end

    test "shows empty state when no tokens for company", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/tokens")
      assert html =~ "No API tokens yet"
    end

    test "shows only tokens for current company", %{conn: conn, user: user, company: company} do
      {:ok, %{api_token: visible_token}} =
        Accounts.create_api_token(user.id, company.id, %{name: "This Company Token"})

      other_company = insert(:company)
      insert(:membership, user: user, company: other_company, role: :owner)

      {:ok, %{api_token: hidden_token}} =
        Accounts.create_api_token(user.id, other_company.id, %{name: "Other Company Token"})

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/tokens")

      assert has_element?(
               view,
               "[data-testid='token-name-#{visible_token.id}']",
               "This Company Token"
             )

      refute has_element?(view, "[data-testid='token-name-#{hidden_token.id}']")
    end
  end

  describe "access control" do
    test "reviewer can access tokens page", %{company: company} do
      {:ok, reviewer} =
        Accounts.get_or_create_google_user(%{
          uid: "g-tok-reviewer",
          email: "reviewer@example.com",
          name: "Reviewer"
        })

      insert(:membership, user: reviewer, company: company, role: :reviewer)

      conn =
        build_conn()
        |> log_in_user(reviewer, %{current_company_id: company.id})

      assert {:ok, _view, _html} = live(conn, ~p"/c/#{company.id}/settings/tokens")
    end

    test "non-member is redirected away", %{company: company} do
      {:ok, non_member} =
        Accounts.get_or_create_google_user(%{
          uid: "g-tok-nonmember",
          email: "nonmember@example.com",
          name: "Non-Member"
        })

      conn =
        build_conn()
        |> log_in_user(non_member, %{current_company_id: company.id})

      assert {:error, {:redirect, %{to: "/companies", flash: %{"error" => message}}}} =
               live(conn, ~p"/c/#{company.id}/settings/tokens")

      assert message =~ "access"
    end
  end

  describe "create token" do
    test "New Token button navigates to form page", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/tokens")

      assert has_element?(view, "a", "New Token")

      assert view
             |> element("a", "New Token")
             |> render_click()
             |> follow_redirect(conn, ~p"/c/#{company.id}/settings/tokens/new")
    end

    test "creates token and shows plaintext", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/tokens/new")

      view
      |> element("form[phx-submit=create]")
      |> render_submit(%{token: %{name: "My Token", description: "For testing"}})

      html = render(view)
      assert html =~ "Copy your API token now"
      assert has_element?(view, "a", "Done")
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

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/tokens")

      view |> element("button", "Revoke") |> render_click()

      html = render(view)
      assert html =~ "Revoked"
    end
  end

  describe "token form navigation" do
    test "Done button navigates back to token list", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/tokens/new")

      view
      |> element("form[phx-submit=create]")
      |> render_submit(%{token: %{name: "Nav Test", description: ""}})

      assert render(view) =~ "Copy your API token now"
      assert has_element?(view, "a", "Done")
    end
  end
end
