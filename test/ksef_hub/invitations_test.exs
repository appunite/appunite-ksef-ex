defmodule KsefHub.InvitationsTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invitations
  alias KsefHub.Invitations.Invitation

  describe "create_invitation/2" do
    setup do
      company = insert(:company)
      owner = insert(:user)
      insert(:membership, user: owner, company: company, role: "owner")
      %{company: company, owner: owner}
    end

    test "owner creates invitation, token generated and hashed in DB", %{
      company: company,
      owner: owner
    } do
      attrs = %{email: "new@example.com", role: "accountant"}

      assert {:ok, %{invitation: %Invitation{} = invitation, token: token}} =
               Invitations.create_invitation(owner.id, company.id, attrs)

      assert invitation.email == "new@example.com"
      assert invitation.role == "accountant"
      assert invitation.status == "pending"
      assert invitation.company_id == company.id
      assert invitation.invited_by_id == owner.id
      assert is_binary(token)
      assert String.length(token) > 0

      # Token hash in DB should match hashing the returned token
      expected_hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
      assert invitation.token_hash == expected_hash

      # Expires in ~7 days
      diff = DateTime.diff(invitation.expires_at, DateTime.utc_now())
      assert diff > 6 * 24 * 3600
      assert diff <= 7 * 24 * 3600
    end

    test "rejects if email already has membership for the company", %{
      company: company,
      owner: owner
    } do
      existing_user = insert(:user, email: "existing@example.com")
      insert(:membership, user: existing_user, company: company, role: "accountant")

      attrs = %{email: "existing@example.com", role: "accountant"}

      assert {:error, :already_member} =
               Invitations.create_invitation(owner.id, company.id, attrs)
    end

    test "rejects if pending invitation already exists", %{company: company, owner: owner} do
      insert(:invitation, company: company, invited_by: owner, email: "dupe@example.com")

      attrs = %{email: "dupe@example.com", role: "reviewer"}

      assert {:error, changeset} = Invitations.create_invitation(owner.id, company.id, attrs)
      assert "already has a pending invitation for this company" in errors_on(changeset)[:email]
    end

    test "rejects non-owner caller", %{company: company} do
      non_owner = insert(:user)
      insert(:membership, user: non_owner, company: company, role: "accountant")

      attrs = %{email: "new@example.com", role: "accountant"}

      assert {:error, :unauthorized} =
               Invitations.create_invitation(non_owner.id, company.id, attrs)
    end

    test "rejects user with no membership", %{company: company} do
      outsider = insert(:user)

      attrs = %{email: "new@example.com", role: "accountant"}

      assert {:error, :unauthorized} =
               Invitations.create_invitation(outsider.id, company.id, attrs)
    end

    test "normalizes email to lowercase", %{company: company, owner: owner} do
      attrs = %{email: "UPPER@Example.COM", role: "accountant"}

      assert {:ok, %{invitation: invitation}} =
               Invitations.create_invitation(owner.id, company.id, attrs)

      assert invitation.email == "upper@example.com"
    end
  end

  describe "accept_invitation/1" do
    setup do
      company = insert(:company)
      owner = insert(:user)
      insert(:membership, user: owner, company: company, role: "owner")
      %{company: company, owner: owner}
    end

    test "valid token creates membership and marks accepted", %{
      company: company,
      owner: owner
    } do
      attrs = %{email: "accepter@example.com", role: "accountant"}

      {:ok, %{invitation: _invitation, token: token}} =
        Invitations.create_invitation(owner.id, company.id, attrs)

      accepter = insert(:user, email: "accepter@example.com")

      assert {:ok, %{invitation: accepted_invitation, membership: membership}} =
               Invitations.accept_invitation(token, accepter)

      assert accepted_invitation.status == "accepted"
      assert membership.user_id == accepter.id
      assert membership.company_id == company.id
      assert membership.role == "accountant"
    end

    test "rejects expired token", %{company: company, owner: owner} do
      attrs = %{email: "expired@example.com", role: "accountant"}

      {:ok, %{invitation: invitation, token: token}} =
        Invitations.create_invitation(owner.id, company.id, attrs)

      # Manually set expires_at to the past
      invitation
      |> Ecto.Changeset.change(
        expires_at: DateTime.add(DateTime.utc_now(), -3600) |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      accepter = insert(:user, email: "expired@example.com")

      assert {:error, :expired} = Invitations.accept_invitation(token, accepter)
    end

    test "rejects invalid token" do
      user = insert(:user)
      assert {:error, :not_found} = Invitations.accept_invitation("bogus-token", user)
    end

    test "rejects already accepted invitation", %{company: company, owner: owner} do
      attrs = %{email: "double@example.com", role: "accountant"}

      {:ok, %{invitation: _invitation, token: token}} =
        Invitations.create_invitation(owner.id, company.id, attrs)

      accepter = insert(:user, email: "double@example.com")
      {:ok, _} = Invitations.accept_invitation(token, accepter)

      assert {:error, :not_found} = Invitations.accept_invitation(token, accepter)
    end

    test "rejects if user already a member", %{company: company, owner: owner} do
      attrs = %{email: "member@example.com", role: "accountant"}

      {:ok, %{invitation: _invitation, token: token}} =
        Invitations.create_invitation(owner.id, company.id, attrs)

      member = insert(:user, email: "member@example.com")
      insert(:membership, user: member, company: company, role: "reviewer")

      assert {:error, :already_member} = Invitations.accept_invitation(token, member)
    end
  end

  describe "cancel_invitation/2" do
    test "owner cancels pending invitation" do
      company = insert(:company)
      owner = insert(:user)
      insert(:membership, user: owner, company: company, role: "owner")

      {:ok, %{invitation: invitation}} =
        Invitations.create_invitation(owner.id, company.id, %{
          email: "cancel@example.com",
          role: "accountant"
        })

      assert {:ok, cancelled} = Invitations.cancel_invitation(owner.id, invitation.id)
      assert cancelled.status == "cancelled"
    end

    test "non-owner cannot cancel invitation" do
      company = insert(:company)
      owner = insert(:user)
      non_owner = insert(:user)
      insert(:membership, user: owner, company: company, role: "owner")
      insert(:membership, user: non_owner, company: company, role: "accountant")

      {:ok, %{invitation: invitation}} =
        Invitations.create_invitation(owner.id, company.id, %{
          email: "cancel2@example.com",
          role: "accountant"
        })

      assert {:error, :unauthorized} = Invitations.cancel_invitation(non_owner.id, invitation.id)
    end

    test "owner of another company cannot cancel invitation (cross-tenant)" do
      company_a = insert(:company)
      company_b = insert(:company)
      owner_a = insert(:user)
      owner_b = insert(:user)
      insert(:membership, user: owner_a, company: company_a, role: "owner")
      insert(:membership, user: owner_b, company: company_b, role: "owner")

      {:ok, %{invitation: invitation}} =
        Invitations.create_invitation(owner_a.id, company_a.id, %{
          email: "cross-tenant@example.com",
          role: "accountant"
        })

      assert {:error, :unauthorized} = Invitations.cancel_invitation(owner_b.id, invitation.id)
    end

    test "cannot cancel non-pending invitation" do
      company = insert(:company)
      owner = insert(:user)
      insert(:membership, user: owner, company: company, role: "owner")

      {:ok, %{invitation: invitation, token: token}} =
        Invitations.create_invitation(owner.id, company.id, %{
          email: "accepted@example.com",
          role: "accountant"
        })

      accepter = insert(:user, email: "accepted@example.com")
      {:ok, _} = Invitations.accept_invitation(token, accepter)

      assert {:error, :not_found} = Invitations.cancel_invitation(owner.id, invitation.id)
    end
  end

  describe "list_pending_invitations/1" do
    test "returns only pending invitations for a company" do
      company = insert(:company)
      other_company = insert(:company)
      owner = insert(:user)
      insert(:membership, user: owner, company: company, role: "owner")
      insert(:membership, user: owner, company: other_company, role: "owner")

      {:ok, %{invitation: inv1}} =
        Invitations.create_invitation(owner.id, company.id, %{
          email: "a@example.com",
          role: "accountant"
        })

      {:ok, %{invitation: _inv2, token: token}} =
        Invitations.create_invitation(owner.id, company.id, %{
          email: "b@example.com",
          role: "reviewer"
        })

      # Accept one
      accepter = insert(:user, email: "b@example.com")
      {:ok, _} = Invitations.accept_invitation(token, accepter)

      # Create one in another company
      {:ok, _} =
        Invitations.create_invitation(owner.id, other_company.id, %{
          email: "c@example.com",
          role: "accountant"
        })

      pending = Invitations.list_pending_invitations(company.id)
      assert length(pending) == 1
      assert hd(pending).id == inv1.id
    end
  end

  describe "accept_pending_invitations_for_email/1" do
    test "auto-accepts all pending invitations for the given email" do
      company1 = insert(:company)
      company2 = insert(:company)
      owner1 = insert(:user)
      owner2 = insert(:user)
      insert(:membership, user: owner1, company: company1, role: "owner")
      insert(:membership, user: owner2, company: company2, role: "owner")

      {:ok, _} =
        Invitations.create_invitation(owner1.id, company1.id, %{
          email: "newuser@example.com",
          role: "accountant"
        })

      {:ok, _} =
        Invitations.create_invitation(owner2.id, company2.id, %{
          email: "newuser@example.com",
          role: "reviewer"
        })

      new_user = insert(:user, email: "newuser@example.com")
      assert {:ok, memberships} = Invitations.accept_pending_invitations_for_email(new_user)

      assert length(memberships) == 2
      company_ids = Enum.map(memberships, & &1.company_id) |> Enum.sort()
      assert company_ids == Enum.sort([company1.id, company2.id])
    end

    test "returns empty list when no pending invitations" do
      user = insert(:user, email: "nobody@example.com")
      assert {:ok, []} = Invitations.accept_pending_invitations_for_email(user)
    end

    test "skips expired invitations" do
      company = insert(:company)
      owner = insert(:user)
      insert(:membership, user: owner, company: company, role: "owner")

      {:ok, %{invitation: invitation}} =
        Invitations.create_invitation(owner.id, company.id, %{
          email: "expired@example.com",
          role: "accountant"
        })

      # Expire it
      invitation
      |> Ecto.Changeset.change(
        expires_at: DateTime.add(DateTime.utc_now(), -3600) |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      user = insert(:user, email: "expired@example.com")
      assert {:ok, []} = Invitations.accept_pending_invitations_for_email(user)
    end
  end
end
