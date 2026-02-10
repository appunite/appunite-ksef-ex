defmodule KsefHubWeb.InvitationAcceptLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Invitations

  setup %{conn: conn} do
    company = insert(:company, name: "Acme Corp")
    owner = insert(:user)
    insert(:membership, user: owner, company: company, role: "owner")
    %{conn: conn, company: company, owner: owner}
  end

  describe "logged-in user" do
    setup %{conn: conn, company: company, owner: owner} do
      {:ok, user} =
        Accounts.get_or_create_google_user(%{
          uid: "g-accept-1",
          email: "accepter@example.com",
          name: "Accepter"
        })

      {:ok, %{token: token}} =
        Invitations.create_invitation(owner.id, company.id, %{
          email: "accepter@example.com",
          role: "accountant"
        })

      conn = log_in_user(conn, user)
      %{conn: conn, token: token, user: user}
    end

    test "accepts invitation and redirects to dashboard", %{conn: conn, token: token} do
      assert {:error, {:redirect, %{to: "/dashboard", flash: flash}}} =
               live(conn, ~p"/invitations/accept/#{token}")

      assert flash["info"] =~ "Invitation accepted"
    end

    test "shows error for expired token", %{conn: conn, company: company, owner: owner} do
      {:ok, %{invitation: invitation, token: expired_token}} =
        Invitations.create_invitation(owner.id, company.id, %{
          email: "expired-accept@example.com",
          role: "accountant"
        })

      invitation
      |> Ecto.Changeset.change(
        expires_at: DateTime.add(DateTime.utc_now(), -3600) |> DateTime.truncate(:second)
      )
      |> KsefHub.Repo.update!()

      {:ok, _user} =
        Accounts.get_or_create_google_user(%{
          uid: "g-expired-1",
          email: "expired-accept@example.com",
          name: "Expired"
        })

      expired_conn =
        log_in_user(
          conn,
          KsefHub.Repo.get_by!(KsefHub.Accounts.User, email: "expired-accept@example.com")
        )

      {:ok, _view, html} = live(expired_conn, ~p"/invitations/accept/#{expired_token}")
      assert html =~ "expired"
    end

    test "shows error for invalid token", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/invitations/accept/bogus-token")
      assert html =~ "invalid"
    end
  end

  describe "unauthenticated user" do
    test "redirects to login with return URL", %{conn: conn, company: company, owner: owner} do
      {:ok, %{token: token}} =
        Invitations.create_invitation(owner.id, company.id, %{
          email: "newbie@example.com",
          role: "accountant"
        })

      assert {:error, {:redirect, %{to: redirect_to, flash: flash}}} =
               live(conn, ~p"/invitations/accept/#{token}")

      assert redirect_to =~ "/users/log-in"
      assert redirect_to =~ "return_to="
      assert redirect_to =~ URI.encode("/invitations/accept/#{token}")
      assert flash["info"] =~ "log in or sign up"
    end
  end
end
