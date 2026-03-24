defmodule KsefHubWeb.TeamMemberLive.ShowTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Companies
  alias KsefHub.Invitations

  setup %{conn: conn} do
    {:ok, owner} =
      Accounts.get_or_create_google_user(%{
        uid: "g-detail-owner",
        email: "owner@example.com",
        name: "Owner"
      })

    company = insert(:company, name: "Detail Corp")
    owner_membership = insert(:membership, user: owner, company: company, role: :owner)

    conn = log_in_user(conn, owner, %{current_company_id: company.id})
    %{conn: conn, owner: owner, company: company, owner_membership: owner_membership}
  end

  describe "member detail - mount" do
    test "renders member detail page", %{conn: conn, company: company} do
      member = insert(:user, name: "Bob", email: "bob@example.com")
      membership = insert(:membership, user: member, company: company, role: :accountant)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team/members/#{membership.id}")

      assert has_element?(view, "[data-testid='member-email']", "bob@example.com")
      assert has_element?(view, "[data-testid='name-form']")
    end

    test "redirects when member not found", %{conn: conn, company: company} do
      {:ok, _view, html} =
        live(conn, ~p"/c/#{company.id}/team/members/#{Ecto.UUID.generate()}")
        |> follow_redirect(conn, ~p"/c/#{company.id}/team")

      assert html =~ "Member not found"
    end
  end

  describe "member detail - edit name" do
    test "can update member name", %{conn: conn, company: company} do
      member = insert(:user, name: "Old Name", email: "rename@example.com")
      membership = insert(:membership, user: member, company: company, role: :accountant)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team/members/#{membership.id}")

      view
      |> form("[data-testid='name-form']", %{"user" => %{"name" => "New Name"}})
      |> render_submit()

      assert has_element?(view, "#flash-info", "Changes saved")

      updated_user = Accounts.get_user!(member.id)
      assert updated_user.name == "New Name"
    end
  end

  describe "member detail - save name and role together" do
    test "can update name and role in one save", %{conn: conn, company: company} do
      member = insert(:user, name: "Old Name", email: "both@example.com")
      membership = insert(:membership, user: member, company: company, role: :accountant)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team/members/#{membership.id}")

      view
      |> form("[data-testid='name-form']", %{
        "user" => %{"name" => "New Name", "role" => "reviewer"}
      })
      |> render_submit()

      assert has_element?(view, "#flash-info", "Changes saved")

      updated_user = Accounts.get_user!(member.id)
      assert updated_user.name == "New Name"

      updated_membership = Companies.get_membership(member.id, company.id)
      assert updated_membership.role == :reviewer
    end
  end

  describe "member detail - role description" do
    test "role description updates when role select changes", %{conn: conn, company: company} do
      member = insert(:user, name: "Desc Test", email: "desc@example.com")
      membership = insert(:membership, user: member, company: company, role: :accountant)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team/members/#{membership.id}")

      # Initial description for accountant
      assert render(view) =~ "Read-only invoice access"

      # Change to reviewer via validate event
      render_change(view, "validate_member", %{
        "user" => %{"name" => "Desc Test", "role" => "reviewer"}
      })

      assert render(view) =~ "expense invoices"
    end
  end

  describe "member detail - change role" do
    test "owner can change member role", %{conn: conn, company: company} do
      member = insert(:user, name: "Role Target", email: "role@example.com")
      membership = insert(:membership, user: member, company: company, role: :accountant)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team/members/#{membership.id}")
      assert has_element?(view, "[data-testid='role-select']")

      view
      |> form("[data-testid='name-form']", %{
        "user" => %{"name" => "Role Target", "role" => "reviewer"}
      })
      |> render_submit()

      assert has_element?(view, "#flash-info", "Changes saved")

      updated = Companies.get_membership(member.id, company.id)
      assert updated.role == :reviewer
    end

    test "cannot change own role", %{conn: conn, company: company, owner_membership: om} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team/members/#{om.id}")

      # Owner's own detail page should not show role select
      refute has_element?(view, "[data-testid='role-select']")
    end

    test "cannot change owner's role", %{conn: conn, company: company, owner_membership: om} do
      {:ok, admin} =
        Accounts.get_or_create_google_user(%{
          uid: "g-detail-admin",
          email: "admin@example.com",
          name: "Admin"
        })

      insert(:membership, user: admin, company: company, role: :admin)
      admin_conn = log_in_user(conn, admin, %{current_company_id: company.id})

      {:ok, view, _html} = live(admin_conn, ~p"/c/#{company.id}/team/members/#{om.id}")

      # Owner detail page should show read-only role badge, not select
      refute has_element?(view, "[data-testid='role-select']")
    end
  end

  describe "member detail - block/unblock" do
    test "owner can block a member", %{conn: conn, company: company} do
      member = insert(:user, name: "Block Me", email: "block@example.com")
      membership = insert(:membership, user: member, company: company, role: :accountant)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team/members/#{membership.id}")
      assert has_element?(view, "[data-testid='block-button']")

      view
      |> element("[data-testid='block-button']")
      |> render_click()

      assert has_element?(view, "#flash-info", "Member blocked")
      assert has_element?(view, "[data-testid='blocked-badge']")

      # Blocked member loses access
      assert is_nil(Companies.get_membership(member.id, company.id))
    end

    test "owner can unblock a blocked member", %{conn: conn, company: company} do
      member = insert(:user, name: "Unblock Me", email: "unblock@example.com")

      membership =
        insert(:membership, user: member, company: company, role: :accountant, status: :blocked)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team/members/#{membership.id}")
      assert has_element?(view, "[data-testid='unblock-button']")

      view
      |> element("[data-testid='unblock-button']")
      |> render_click()

      assert has_element?(view, "#flash-info", "Member unblocked")
      refute has_element?(view, "[data-testid='blocked-badge']")

      assert Companies.get_membership(member.id, company.id) != nil
    end

    test "cannot block owner", %{conn: conn, company: company, owner_membership: om} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team/members/#{om.id}")
      refute has_element?(view, "[data-testid='block-button']")
    end

    test "cannot block self", %{conn: conn, company: company, owner_membership: om} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team/members/#{om.id}")
      refute has_element?(view, "[data-testid='block-button']")
    end

    test "server-side rejects blocking owner via crafted event", %{
      conn: conn,
      company: company,
      owner_membership: om
    } do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/team/members/#{om.id}")
      render_click(view, "block_member", %{})
      assert has_element?(view, "#flash-error", "Cannot change owner")
    end

    test "server-side rejects blocking self via crafted event", %{conn: conn, company: company} do
      {:ok, admin} =
        Accounts.get_or_create_google_user(%{
          uid: "g-self-block",
          email: "selfblock@example.com",
          name: "SelfBlock"
        })

      admin_membership = insert(:membership, user: admin, company: company, role: :admin)
      admin_conn = log_in_user(conn, admin, %{current_company_id: company.id})

      {:ok, view, _html} =
        live(admin_conn, ~p"/c/#{company.id}/team/members/#{admin_membership.id}")

      render_click(view, "block_member", %{})
      assert has_element?(view, "#flash-error", "You cannot change your own role")
    end
  end

  describe "member detail - auth enforcement" do
    test "blocked member cannot access the app", %{conn: conn, company: company} do
      member = insert(:user, email: "blocked-user@example.com")
      insert(:membership, user: member, company: company, role: :accountant, status: :blocked)

      blocked_conn = log_in_user(conn, member, %{current_company_id: company.id})

      # Blocked user should be redirected — they have no active companies
      assert {:error, {:redirect, _}} = live(blocked_conn, ~p"/c/#{company.id}/team")
    end
  end

  describe "invitation detail" do
    test "renders invitation detail page", %{conn: conn, company: company, owner: owner} do
      {:ok, %{invitation: invitation}} =
        Invitations.create_invitation(owner.id, company.id, %{
          email: "invitee@example.com",
          role: :reviewer
        })

      {:ok, view, _html} =
        live(conn, ~p"/c/#{company.id}/team/invitations/#{invitation.id}")

      assert has_element?(view, "[data-testid='invitation-email']", "invitee@example.com")
      assert has_element?(view, "[data-testid='invitation-status']", "Pending")
    end

    test "can cancel pending invitation", %{conn: conn, company: company, owner: owner} do
      {:ok, %{invitation: invitation}} =
        Invitations.create_invitation(owner.id, company.id, %{
          email: "cancel@example.com",
          role: :accountant
        })

      {:ok, view, _html} =
        live(conn, ~p"/c/#{company.id}/team/invitations/#{invitation.id}")

      assert has_element?(view, "[data-testid='cancel-invitation-button']")

      view
      |> element("[data-testid='cancel-invitation-button']")
      |> render_click()

      assert has_element?(view, "#flash-info", "Invitation cancelled")
      assert has_element?(view, "[data-testid='invitation-status']", "Cancelled")
    end

    test "redirects when invitation not found", %{conn: conn, company: company} do
      {:ok, _view, html} =
        live(conn, ~p"/c/#{company.id}/team/invitations/#{Ecto.UUID.generate()}")
        |> follow_redirect(conn, ~p"/c/#{company.id}/team")

      assert html =~ "Invitation not found"
    end
  end
end
