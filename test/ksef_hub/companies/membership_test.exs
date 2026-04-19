defmodule KsefHub.Companies.MembershipTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Companies.Membership

  describe "changeset/2" do
    test "valid with IDs on struct and role in attrs" do
      user = insert(:user)
      company = insert(:company)

      changeset =
        %Membership{user_id: user.id, company_id: company.id}
        |> Membership.changeset(%{role: :owner})

      assert changeset.valid?
    end

    test "requires user_id" do
      company = insert(:company)

      changeset =
        %Membership{company_id: company.id}
        |> Membership.changeset(%{role: :owner})

      assert errors_on(changeset).user_id
    end

    test "requires company_id" do
      user = insert(:user)

      changeset =
        %Membership{user_id: user.id}
        |> Membership.changeset(%{role: :owner})

      assert errors_on(changeset).company_id
    end

    test "requires role" do
      user = insert(:user)
      company = insert(:company)

      changeset =
        %Membership{user_id: user.id, company_id: company.id}
        |> Membership.changeset(%{})

      assert errors_on(changeset).role
    end

    test "accepts valid roles" do
      user = insert(:user)
      company = insert(:company)

      for role <- [:owner, :admin, :accountant, :approver, :analyst] do
        changeset =
          %Membership{user_id: user.id, company_id: company.id}
          |> Membership.changeset(%{role: role})

        assert changeset.valid?, "expected role #{role} to be valid"
      end
    end

    test "rejects invalid role" do
      user = insert(:user)
      company = insert(:company)

      changeset =
        %Membership{user_id: user.id, company_id: company.id}
        |> Membership.changeset(%{role: "superadmin"})

      assert "is invalid" in errors_on(changeset).role
    end

    test "does not cast user_id or company_id from attrs" do
      user = insert(:user)
      company = insert(:company)
      other_user = insert(:user)

      changeset =
        %Membership{user_id: user.id, company_id: company.id}
        |> Membership.changeset(%{role: :owner, user_id: other_user.id})

      # user_id should remain as set on the struct, not overwritten by attrs
      assert Ecto.Changeset.get_field(changeset, :user_id) == user.id
    end

    test "enforces unique user+company pair" do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company)

      {:error, changeset} =
        %Membership{user_id: user.id, company_id: company.id}
        |> Membership.changeset(%{role: :accountant})
        |> Repo.insert()

      assert "already a member of this company" in errors_on(changeset).user_id
    end
  end
end
