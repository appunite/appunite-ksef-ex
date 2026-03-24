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
    insert(:membership, user: owner, company: company, role: :owner)

    conn = log_in_user(conn, owner, %{current_company_id: company.id})
    %{conn: conn, owner: owner, company: company}
  end

  describe "mount" do
    test "renders team page for owner", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")
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

      insert(:membership, user: non_owner, company: company, role: :accountant)
      non_owner_conn = log_in_user(conn, non_owner, %{current_company_id: company.id})

      expected_path = "/c/#{company.id}/invoices"

      assert {:error, {:redirect, %{to: ^expected_path, flash: flash}}} =
               live(non_owner_conn, ~p"/c/#{company.id}/team")

      assert flash["error"] =~ "You don't have permission to access this page."
    end
  end

  describe "member list" do
    test "displays all members with role badges", %{conn: conn, company: company} do
      member = insert(:user, name: "Bob Accountant", email: "bob@example.com")
      insert(:membership, user: member, company: company, role: :accountant)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")
      assert has_element?(view, "[data-testid='member-list']")
      assert has_element?(view, "[data-testid='member-list'] td", "Owner")
      assert has_element?(view, "[data-testid='member-list'] td", "Bob Accountant")
    end

    test "member rows are clickable and navigate to detail page", %{
      conn: conn,
      company: company
    } do
      member = insert(:user, name: "Clickable", email: "click@example.com")
      membership = insert(:membership, user: member, company: company, role: :accountant)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")
      assert has_element?(view, "[data-testid='member-row-#{member.id}']")
      assert has_element?(view, "[data-testid='member-link-#{member.id}']")

      view
      |> element("[data-testid='member-link-#{member.id}']")
      |> render_click()

      assert_redirect(view, "/c/#{company.id}/team/members/#{membership.id}")
    end

    test "shows blocked badge for blocked members", %{conn: conn, company: company} do
      member = insert(:user, name: "Blocked User", email: "blocked@example.com")
      insert(:membership, user: member, company: company, role: :accountant, status: :blocked)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")
      assert has_element?(view, "[data-testid='blocked-badge-#{member.id}']", "Blocked")
    end

    test "invitation rows are clickable", %{conn: conn, company: company, owner: owner} do
      {:ok, %{invitation: invitation}} =
        Invitations.create_invitation(owner.id, company.id, %{
          email: "pending@example.com",
          role: :reviewer
        })

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")
      assert has_element?(view, "[data-testid='invitation-row-#{invitation.id}']")
      assert has_element?(view, "[data-testid='invitation-link-#{invitation.id}']")

      view
      |> element("[data-testid='invitation-link-#{invitation.id}']")
      |> render_click()

      assert_redirect(view, ~p"/c/#{company.id}/team/invitations/#{invitation.id}")
    end
  end

  describe "invite member" do
    test "owner can send invitation", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")

      view
      |> form("[data-testid='invite-form']", %{
        "invitation" => %{"email" => "newmember@example.com", "role" => "accountant"}
      })
      |> render_submit()

      assert has_element?(view, "#flash-info", "Invitation sent")
      assert has_element?(view, "[data-testid='team-table'] td", "newmember@example.com")
    end

    test "shows error when inviting existing member", %{conn: conn, company: company} do
      existing = insert(:user, email: "existing@example.com")
      insert(:membership, user: existing, company: company, role: :accountant)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")

      view
      |> form("[data-testid='invite-form']", %{
        "invitation" => %{"email" => "existing@example.com", "role" => "accountant"}
      })
      |> render_submit()

      assert has_element?(view, "#flash-error", "already a member")
    end
  end
end
