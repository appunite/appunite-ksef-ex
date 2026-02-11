defmodule KsefHubWeb.TeamLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Invitations

  setup %{conn: conn} do
    {:ok, owner} =
      Accounts.get_or_create_google_user(%{
        uid: "g-team-owner",
        email: "owner@example.com",
        name: "Owner"
      })

    company = insert(:company, name: "Team Corp")
    insert(:membership, user: owner, company: company, role: "owner")

    conn = log_in_user(conn, owner, %{current_company_id: company.id})
    %{conn: conn, owner: owner, company: company}
  end

  describe "mount" do
    test "renders team page for owner", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/team")
      assert has_element?(view, "h1", "Team")
      assert has_element?(view, "h2", "Members")
    end

    test "non-owner cannot access team page", %{conn: conn, company: company} do
      {:ok, non_owner} =
        Accounts.get_or_create_google_user(%{
          uid: "g-team-nonowner",
          email: "accountant@example.com",
          name: "Accountant"
        })

      insert(:membership, user: non_owner, company: company, role: "accountant")
      non_owner_conn = log_in_user(conn, non_owner, %{current_company_id: company.id})

      assert {:error, {:redirect, %{to: "/dashboard", flash: flash}}} =
               live(non_owner_conn, ~p"/team")

      assert flash["error"] =~ "owner"
    end
  end

  describe "member list" do
    test "displays all members", %{conn: conn, company: company} do
      member = insert(:user, name: "Bob Accountant", email: "bob@example.com")
      insert(:membership, user: member, company: company, role: "accountant")

      {:ok, view, _html} = live(conn, ~p"/team")
      assert has_element?(view, "[data-testid='member-list']")
      assert has_element?(view, "[data-testid='member-list'] td", "Owner")
      assert has_element?(view, "[data-testid='member-list'] td", "Bob Accountant")
    end
  end

  describe "invite member" do
    test "owner can send invitation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/team")

      view
      |> form("[data-testid='invite-form']", %{
        "invitation" => %{"email" => "newmember@example.com", "role" => "accountant"}
      })
      |> render_submit()

      assert has_element?(view, "#flash-info", "Invitation sent")
      assert has_element?(view, "[data-testid='pending-invitations'] td", "newmember@example.com")
    end

    test "shows error when inviting existing member", %{conn: conn, company: company} do
      existing = insert(:user, email: "existing@example.com")
      insert(:membership, user: existing, company: company, role: "accountant")

      {:ok, view, _html} = live(conn, ~p"/team")

      view
      |> form("[data-testid='invite-form']", %{
        "invitation" => %{"email" => "existing@example.com", "role" => "accountant"}
      })
      |> render_submit()

      assert has_element?(view, "#flash-error", "already a member")
    end
  end

  describe "pending invitations" do
    test "displays pending invitations", %{conn: conn, company: company, owner: owner} do
      {:ok, _} =
        Invitations.create_invitation(owner.id, company.id, %{
          email: "pending@example.com",
          role: "reviewer"
        })

      {:ok, view, _html} = live(conn, ~p"/team")
      assert has_element?(view, "[data-testid='pending-invitations'] td", "pending@example.com")
      assert has_element?(view, "[data-testid='pending-invitations'] .badge", "reviewer")
    end

    test "owner can cancel pending invitation", %{conn: conn, company: company, owner: owner} do
      {:ok, %{invitation: invitation}} =
        Invitations.create_invitation(owner.id, company.id, %{
          email: "cancel-me@example.com",
          role: "accountant"
        })

      {:ok, view, _html} = live(conn, ~p"/team")
      assert has_element?(view, "[data-testid='pending-invitations'] td", "cancel-me@example.com")

      view
      |> element("[data-testid='cancel-invitation-#{invitation.id}']")
      |> render_click()

      assert has_element?(view, "#flash-info", "Invitation cancelled")

      refute has_element?(
               view,
               "[data-testid='pending-invitations'] td",
               "cancel-me@example.com"
             )
    end
  end

  describe "remove member" do
    test "cannot remove the owner via server-side event", %{conn: conn, owner: owner} do
      {:ok, view, _html} = live(conn, ~p"/team")

      # Simulate sending the event directly (bypassing UI guard)
      render_click(view, "remove_member", %{"user-id" => owner.id})

      assert has_element?(view, "#flash-error", "Cannot remove company owner")
    end

    test "owner can remove a non-owner member", %{conn: conn, company: company} do
      member = insert(:user, name: "Remove Me", email: "removeme@example.com")
      insert(:membership, user: member, company: company, role: "accountant")

      {:ok, view, _html} = live(conn, ~p"/team")
      assert has_element?(view, "[data-testid='member-list'] td", "Remove Me")

      view
      |> element("[data-testid='remove-member-#{member.id}']")
      |> render_click()

      assert has_element?(view, "#flash-info", "Member removed")
      refute has_element?(view, "[data-testid='member-list'] td", "Remove Me")
    end
  end
end
