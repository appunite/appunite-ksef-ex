defmodule KsefHubWeb.TeamLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Companies
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
    test "displays all members", %{conn: conn, company: company} do
      member = insert(:user, name: "Bob Accountant", email: "bob@example.com")
      insert(:membership, user: member, company: company, role: :accountant)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")
      assert has_element?(view, "[data-testid='member-list']")
      assert has_element?(view, "[data-testid='member-list'] td", "Owner")
      assert has_element?(view, "[data-testid='member-list'] td", "Bob Accountant")
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

  describe "pending invitations" do
    test "displays pending invitations", %{conn: conn, company: company, owner: owner} do
      {:ok, _} =
        Invitations.create_invitation(owner.id, company.id, %{
          email: "pending@example.com",
          role: :reviewer
        })

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")
      assert has_element?(view, "[data-testid='team-table'] td", "pending@example.com")
      assert has_element?(view, "#pending-invitations-list select[data-role='reviewer']")
    end

    test "owner can cancel pending invitation", %{conn: conn, company: company, owner: owner} do
      {:ok, %{invitation: invitation}} =
        Invitations.create_invitation(owner.id, company.id, %{
          email: "cancel-me@example.com",
          role: :accountant
        })

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")
      assert has_element?(view, "[data-testid='team-table'] td", "cancel-me@example.com")

      view
      |> element("[data-testid='cancel-invitation-#{invitation.id}']")
      |> render_click()

      assert has_element?(view, "#flash-info", "Invitation cancelled")

      refute has_element?(
               view,
               "[data-testid='team-table'] td",
               "cancel-me@example.com"
             )
    end
  end

  describe "change role" do
    test "owner can change accountant to reviewer", %{conn: conn, company: company} do
      member = insert(:user, name: "Role Target", email: "target@example.com")
      insert(:membership, user: member, company: company, role: :accountant)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")
      assert has_element?(view, "[data-testid='role-select-#{member.id}']")

      render_change(view, "change_role", %{"user-id" => member.id, "role" => "reviewer"})

      assert has_element?(view, "#flash-info", "Role updated")

      membership = Companies.get_membership(member.id, company.id)
      assert membership.role == :reviewer
    end

    test "no role select shown for owner member", %{conn: conn, company: company, owner: owner} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")
      refute has_element?(view, "[data-testid='role-select-#{owner.id}']")
    end

    test "cannot change own role", %{conn: conn, company: company, owner: owner} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")

      render_change(view, "change_role", %{"user-id" => owner.id, "role" => "accountant"})

      assert has_element?(view, "#flash-error", "You cannot change your own role")
    end

    test "cannot change owner's role via server-side event", %{
      conn: conn,
      company: company,
      owner: owner
    } do
      {:ok, admin} =
        Accounts.get_or_create_google_user(%{
          uid: "g-team-admin-owner-guard",
          email: "admin-guard@example.com",
          name: "AdminGuard"
        })

      insert(:membership, user: admin, company: company, role: :admin)
      admin_conn = log_in_user(conn, admin, %{current_company_id: company.id})

      {:ok, view, _html} = live(admin_conn, ~p"/c/#{company.id}/team")

      render_change(view, "change_role", %{"user-id" => owner.id, "role" => "accountant"})

      assert has_element?(view, "#flash-error", "Cannot change owner's role")
    end

    test "admin can change a non-owner role", %{conn: conn, company: company} do
      {:ok, admin} =
        Accounts.get_or_create_google_user(%{
          uid: "g-team-admin",
          email: "admin@example.com",
          name: "Admin"
        })

      insert(:membership, user: admin, company: company, role: :admin)
      admin_conn = log_in_user(conn, admin, %{current_company_id: company.id})

      member = insert(:user, name: "Admin Target", email: "admin-target@example.com")
      insert(:membership, user: member, company: company, role: :accountant)

      {:ok, view, _html} = live(admin_conn, ~p"/c/#{company.id}/team")

      render_change(view, "change_role", %{"user-id" => member.id, "role" => "reviewer"})

      assert has_element?(view, "#flash-info", "Role updated")

      membership = Companies.get_membership(member.id, company.id)
      assert membership.role == :reviewer
    end

    test "rejects invalid role string", %{conn: conn, company: company} do
      member = insert(:user, email: "invalid-role-target@example.com")
      insert(:membership, user: member, company: company, role: :accountant)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")

      render_change(view, "change_role", %{"user-id" => member.id, "role" => "superadmin"})

      assert has_element?(view, "#flash-error", "Invalid role")
    end

    test "returns error for non-existent member", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")

      render_change(view, "change_role", %{
        "user-id" => Ecto.UUID.generate(),
        "role" => "reviewer"
      })

      assert has_element?(view, "#flash-error", "Member not found")
    end

    test "select reflects new role after change", %{conn: conn, company: company} do
      member = insert(:user, email: "reflect@example.com")
      insert(:membership, user: member, company: company, role: :accountant)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")

      render_change(view, "change_role", %{"user-id" => member.id, "role" => "reviewer"})

      assert has_element?(
               view,
               "[data-testid='role-select-#{member.id}'] option[selected][value='reviewer']"
             )
    end

    test "admin cannot promote to owner", %{conn: conn, company: company} do
      {:ok, admin} =
        Accounts.get_or_create_google_user(%{
          uid: "g-team-admin-noowner",
          email: "admin2@example.com",
          name: "Admin2"
        })

      insert(:membership, user: admin, company: company, role: :admin)
      admin_conn = log_in_user(conn, admin, %{current_company_id: company.id})

      member = insert(:user, name: "No Owner", email: "no-owner@example.com")
      insert(:membership, user: member, company: company, role: :accountant)

      {:ok, view, _html} = live(admin_conn, ~p"/c/#{company.id}/team")

      render_change(view, "change_role", %{"user-id" => member.id, "role" => "owner"})

      assert has_element?(view, "#flash-error", "Invalid role")

      membership = Companies.get_membership(member.id, company.id)
      assert membership.role == :accountant
    end
  end

  describe "remove member" do
    test "cannot remove the owner via server-side event", %{
      conn: conn,
      company: company,
      owner: owner
    } do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")

      # Simulate sending the event directly (bypassing UI guard)
      render_click(view, "remove_member", %{"user-id" => owner.id})

      assert has_element?(view, "#flash-error", "Cannot remove company owner")
    end

    test "owner can remove a non-owner member", %{conn: conn, company: company} do
      member = insert(:user, name: "Remove Me", email: "removeme@example.com")
      insert(:membership, user: member, company: company, role: :accountant)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team")
      assert has_element?(view, "[data-testid='member-list'] td", "Remove Me")

      view
      |> element("[data-testid='remove-member-#{member.id}']")
      |> render_click()

      assert has_element?(view, "#flash-info", "Member removed")
      refute has_element?(view, "[data-testid='member-list'] td", "Remove Me")
    end
  end
end
