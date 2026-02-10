defmodule KsefHub.Companies.MembershipTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Companies.Membership

  describe "changeset/2" do
    test "valid with required fields" do
      user = insert(:user)
      company = insert(:company)

      changeset =
        Membership.changeset(%Membership{}, %{
          user_id: user.id,
          company_id: company.id,
          role: "owner"
        })

      assert changeset.valid?
    end

    test "requires user_id" do
      company = insert(:company)

      changeset =
        Membership.changeset(%Membership{}, %{
          company_id: company.id,
          role: "owner"
        })

      assert errors_on(changeset).user_id
    end

    test "requires company_id" do
      user = insert(:user)

      changeset =
        Membership.changeset(%Membership{}, %{
          user_id: user.id,
          role: "owner"
        })

      assert errors_on(changeset).company_id
    end

    test "requires role" do
      user = insert(:user)
      company = insert(:company)

      changeset =
        Membership.changeset(%Membership{}, %{
          user_id: user.id,
          company_id: company.id
        })

      assert errors_on(changeset).role
    end

    test "accepts valid roles" do
      user = insert(:user)
      company = insert(:company)

      for role <- ~w(owner accountant invoice_reviewer) do
        changeset =
          Membership.changeset(%Membership{}, %{
            user_id: user.id,
            company_id: company.id,
            role: role
          })

        assert changeset.valid?, "expected role #{role} to be valid"
      end
    end

    test "rejects invalid role" do
      user = insert(:user)
      company = insert(:company)

      changeset =
        Membership.changeset(%Membership{}, %{
          user_id: user.id,
          company_id: company.id,
          role: "admin"
        })

      assert "is invalid" in errors_on(changeset).role
    end

    test "enforces unique user+company pair" do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company)

      {:error, changeset} =
        %Membership{}
        |> Membership.changeset(%{
          user_id: user.id,
          company_id: company.id,
          role: "accountant"
        })
        |> Repo.insert()

      assert "already a member of this company" in errors_on(changeset).user_id
    end
  end
end
