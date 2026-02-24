defmodule KsefHubWeb.InvitationAutoAcceptTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  alias KsefHub.Companies
  alias KsefHub.Invitations

  describe "registration auto-accept" do
    test "sign up with pending invitation auto-creates membership", %{conn: conn} do
      company = insert(:company, name: "Pending Corp")
      owner = insert(:user)
      insert(:membership, user: owner, company: company, role: :owner)

      {:ok, _} =
        Invitations.create_invitation(owner.id, company.id, %{
          email: "newuser@example.com",
          role: "accountant"
        })

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      form =
        form(lv, "#registration_form", %{
          "user" => %{
            "email" => "newuser@example.com",
            "password" => "valid_password123"
          }
        })

      render_submit(form)
      conn = follow_trigger_action(form, conn)
      assert redirected_to(conn) =~ "/dashboard"

      # Verify membership was auto-created
      user = KsefHub.Accounts.get_user_by_email("newuser@example.com")
      assert user

      membership = Companies.get_membership(user.id, company.id)
      assert membership
      assert membership.role == :accountant
    end
  end
end
