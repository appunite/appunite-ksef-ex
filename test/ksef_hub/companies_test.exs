defmodule KsefHub.CompaniesTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Companies
  alias KsefHub.Companies.{Company, Membership}

  describe "create_company/1" do
    test "creates a company with valid attributes" do
      attrs = %{name: "Acme Sp. z o.o.", nip: "1234567890"}
      assert {:ok, %Company{} = company} = Companies.create_company(attrs)
      assert company.name == "Acme Sp. z o.o."
      assert company.nip == "1234567890"
      assert company.is_active == true
    end

    test "creates a company with address" do
      attrs = %{name: "Acme", nip: "1234567890", address: "ul. Testowa 1, Warszawa"}
      assert {:ok, %Company{} = company} = Companies.create_company(attrs)
      assert company.address == "ul. Testowa 1, Warszawa"
    end

    test "requires name" do
      assert {:error, changeset} = Companies.create_company(%{nip: "1234567890"})
      assert errors_on(changeset).name
    end

    test "requires NIP" do
      assert {:error, changeset} = Companies.create_company(%{name: "Acme"})
      assert errors_on(changeset).nip
    end

    test "rejects NIP that is too short" do
      assert {:error, changeset} = Companies.create_company(%{name: "Acme", nip: "12345"})
      assert "must be a 10-digit NIP" in errors_on(changeset).nip
    end

    test "rejects NIP that is too long" do
      assert {:error, changeset} = Companies.create_company(%{name: "Acme", nip: "12345678901"})
      assert "must be a 10-digit NIP" in errors_on(changeset).nip
    end

    test "rejects NIP with non-digit characters" do
      assert {:error, changeset} = Companies.create_company(%{name: "Acme", nip: "123456789a"})
      assert "must be a 10-digit NIP" in errors_on(changeset).nip
    end

    test "enforces unique NIP" do
      insert(:company, nip: "1234567890")
      assert {:error, changeset} = Companies.create_company(%{name: "Other", nip: "1234567890"})
      assert "has already been taken" in errors_on(changeset).nip
    end
  end

  describe "list_companies/0" do
    test "returns all active companies ordered by name" do
      insert(:company, name: "Company A")
      insert(:company, name: "Company B")
      insert(:company, name: "Company C", is_active: false)

      companies = Companies.list_companies()
      assert length(companies) == 2
      assert [%{name: "Company A"}, %{name: "Company B"}] = companies
    end

    test "returns empty list when no companies" do
      assert Companies.list_companies() == []
    end
  end

  describe "get_company!/1" do
    test "returns the company with the given id" do
      company = insert(:company)
      assert Companies.get_company!(company.id).id == company.id
    end

    test "raises when company not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Companies.get_company!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_company/1" do
    test "returns the company with the given id" do
      company = insert(:company)
      assert %Company{} = Companies.get_company(company.id)
    end

    test "returns nil when company not found" do
      assert Companies.get_company(Ecto.UUID.generate()) == nil
    end
  end

  describe "update_company/2" do
    test "updates the company name" do
      company = insert(:company)
      assert {:ok, updated} = Companies.update_company(company, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "does not allow changing NIP to invalid" do
      company = insert(:company)
      assert {:error, changeset} = Companies.update_company(company, %{nip: "bad"})
      assert "must be a 10-digit NIP" in errors_on(changeset).nip
    end

    test "enforces unique NIP on update" do
      insert(:company, nip: "1111111111")
      company = insert(:company, nip: "2222222222")
      assert {:error, changeset} = Companies.update_company(company, %{nip: "1111111111"})
      assert "has already been taken" in errors_on(changeset).nip
    end
  end

  describe "list_companies_for_user/1" do
    test "returns only companies where user has membership" do
      user = insert(:user)
      company_a = insert(:company, name: "Alpha")
      company_b = insert(:company, name: "Beta")
      _company_c = insert(:company, name: "Gamma")

      insert(:membership, user: user, company: company_a, role: :owner)
      insert(:membership, user: user, company: company_b, role: :accountant)

      companies = Companies.list_companies_for_user(user.id)
      assert length(companies) == 2
      assert Enum.map(companies, & &1.name) == ["Alpha", "Beta"]
    end

    test "returns empty list for user with no memberships" do
      user = insert(:user)
      _company = insert(:company)

      assert Companies.list_companies_for_user(user.id) == []
    end

    test "does not return inactive companies" do
      user = insert(:user)
      company = insert(:company, is_active: false)
      insert(:membership, user: user, company: company)

      assert Companies.list_companies_for_user(user.id) == []
    end

    test "does not return other users' companies" do
      user_a = insert(:user)
      user_b = insert(:user)
      company = insert(:company)

      insert(:membership, user: user_a, company: company)

      assert Companies.list_companies_for_user(user_b.id) == []
    end
  end

  describe "list_companies_for_user_with_credential_status/1" do
    test "returns companies with credential status for user" do
      user = insert(:user)
      company = insert(:company, name: "WithCred")
      insert(:membership, user: user, company: company)
      insert(:credential, company: company, is_active: true)

      companies = Companies.list_companies_for_user_with_credential_status(user.id)
      assert length(companies) == 1
      assert hd(companies).has_active_credential == true
    end

    test "returns false for company without credential" do
      user = insert(:user)
      company = insert(:company, name: "NoCred")
      insert(:membership, user: user, company: company)

      companies = Companies.list_companies_for_user_with_credential_status(user.id)
      assert length(companies) == 1
      assert hd(companies).has_active_credential == false
    end

    test "returns only user's companies" do
      user = insert(:user)
      other_user = insert(:user)
      company_a = insert(:company)
      company_b = insert(:company)
      insert(:membership, user: user, company: company_a)
      insert(:membership, user: other_user, company: company_b)

      companies = Companies.list_companies_for_user_with_credential_status(user.id)
      assert length(companies) == 1
      assert hd(companies).id == company_a.id
    end
  end

  describe "get_membership/2" do
    test "returns membership for user and company" do
      user = insert(:user)
      company = insert(:company)
      membership = insert(:membership, user: user, company: company, role: :accountant)

      assert %Membership{} = found = Companies.get_membership(user.id, company.id)
      assert found.id == membership.id
      assert found.role == :accountant
    end

    test "returns nil when no membership exists" do
      user = insert(:user)
      company = insert(:company)

      assert Companies.get_membership(user.id, company.id) == nil
    end
  end

  describe "get_membership!/2" do
    test "returns membership for user and company" do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      assert %Membership{} = Companies.get_membership!(user.id, company.id)
    end

    test "raises when no membership exists" do
      user = insert(:user)
      company = insert(:company)

      assert_raise Ecto.NoResultsError, fn ->
        Companies.get_membership!(user.id, company.id)
      end
    end
  end

  describe "create_membership/1" do
    test "creates a membership with valid attrs" do
      user = insert(:user)
      company = insert(:company)

      assert {:ok, %Membership{} = membership} =
               Companies.create_membership(%{
                 user_id: user.id,
                 company_id: company.id,
                 role: :accountant
               })

      assert membership.role == :accountant
      assert membership.user_id == user.id
      assert membership.company_id == company.id
    end

    test "rejects duplicate user+company pair" do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company)

      assert {:error, changeset} =
               Companies.create_membership(%{
                 user_id: user.id,
                 company_id: company.id,
                 role: :accountant
               })

      assert "already a member of this company" in errors_on(changeset).user_id
    end
  end

  describe "create_company_with_owner/2" do
    test "atomically creates company and owner membership" do
      user = insert(:user)
      attrs = %{name: "New Co", nip: "1234567890"}

      assert {:ok, %{company: company, membership: membership}} =
               Companies.create_company_with_owner(user, attrs)

      assert company.name == "New Co"
      assert company.nip == "1234567890"
      assert membership.user_id == user.id
      assert membership.company_id == company.id
      assert membership.role == :owner
    end

    test "rolls back if company creation fails" do
      user = insert(:user)
      attrs = %{name: "Bad Co", nip: "bad"}

      assert {:error, :company, changeset, _changes} =
               Companies.create_company_with_owner(user, attrs)

      assert errors_on(changeset).nip
      assert Companies.list_companies_for_user(user.id) == []
    end

    test "rolls back if NIP already taken" do
      insert(:company, nip: "1111111111")
      user = insert(:user)
      attrs = %{name: "Dupe Co", nip: "1111111111"}

      assert {:error, :company, changeset, _changes} =
               Companies.create_company_with_owner(user, attrs)

      assert "has already been taken" in errors_on(changeset).nip
    end
  end

  describe "list_members/1" do
    test "returns memberships with preloaded users for a company" do
      company = insert(:company)
      user1 = insert(:user, name: "Alice")
      user2 = insert(:user, name: "Bob")
      insert(:membership, user: user1, company: company, role: :owner)
      insert(:membership, user: user2, company: company, role: :accountant)

      members = Companies.list_members(company.id)
      assert length(members) == 2
      names = Enum.map(members, & &1.user.name) |> Enum.sort()
      assert names == ["Alice", "Bob"]
    end

    test "does not include members from other companies" do
      company = insert(:company)
      other_company = insert(:company)
      user1 = insert(:user)
      user2 = insert(:user)
      insert(:membership, user: user1, company: company, role: :owner)
      insert(:membership, user: user2, company: other_company, role: :owner)

      members = Companies.list_members(company.id)
      assert length(members) == 1
      assert hd(members).user_id == user1.id
    end
  end

  describe "delete_membership/1" do
    test "deletes a membership" do
      company = insert(:company)
      user = insert(:user)
      membership = insert(:membership, user: user, company: company, role: :accountant)

      assert {:ok, _deleted} = Companies.delete_membership(membership)
      assert is_nil(Companies.get_membership(user.id, company.id))
    end
  end

  describe "update_membership_role/2" do
    test "updates the role of a membership" do
      company = insert(:company)
      user = insert(:user)
      membership = insert(:membership, user: user, company: company, role: :accountant)

      assert {:ok, updated} = Companies.update_membership_role(membership, :reviewer)
      assert updated.role == :reviewer
    end

    test "rejects invalid role" do
      company = insert(:company)
      user = insert(:user)
      membership = insert(:membership, user: user, company: company, role: :accountant)

      assert {:error, changeset} = Companies.update_membership_role(membership, :superadmin)
      assert "is invalid" in errors_on(changeset)[:role]
    end
  end

  describe "has_role?/3" do
    test "returns true when user has the specified role" do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      assert Companies.has_role?(user.id, company.id, :owner)
    end

    test "returns false when user has a different role" do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :accountant)

      refute Companies.has_role?(user.id, company.id, :owner)
    end

    test "returns false when user has no membership" do
      user = insert(:user)
      company = insert(:company)

      refute Companies.has_role?(user.id, company.id, :owner)
    end

    test "accepts a list of roles" do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :accountant)

      assert Companies.has_role?(user.id, company.id, [:owner, :accountant])
      refute Companies.has_role?(user.id, company.id, [:owner, :reviewer])
    end
  end

  describe "enable_inbound_email/1" do
    test "generates an 8-char alphanumeric token and stores plaintext + hash" do
      company = insert(:company)

      assert {:ok, updated} = Companies.enable_inbound_email(company)

      assert is_binary(updated.inbound_email_token)
      assert String.length(updated.inbound_email_token) == 8
      assert updated.inbound_email_token =~ ~r/^[a-z0-9]+$/

      assert is_binary(updated.inbound_email_token_hash)
      assert String.length(updated.inbound_email_token_hash) == 64
    end

    test "regenerates token when called again" do
      company = insert(:company)
      {:ok, first} = Companies.enable_inbound_email(company)
      {:ok, second} = Companies.enable_inbound_email(first)
      assert second.inbound_email_token != first.inbound_email_token
    end

    test "enforces token hash uniqueness" do
      company_a = insert(:company)
      company_b = insert(:company)
      {:ok, a} = Companies.enable_inbound_email(company_a)

      # Manually set the same hash to test uniqueness constraint
      assert {:error, changeset} =
               company_b
               |> Company.inbound_email_token_changeset(%{
                 token: a.inbound_email_token,
                 hash: a.inbound_email_token_hash
               })
               |> KsefHub.Repo.update()

      assert "has already been taken" in errors_on(changeset).inbound_email_token_hash
    end
  end

  describe "disable_inbound_email/1" do
    test "clears the token and hash" do
      company = insert(:company)
      {:ok, enabled} = Companies.enable_inbound_email(company)
      assert enabled.inbound_email_token != nil
      assert enabled.inbound_email_token_hash != nil

      {:ok, disabled} = Companies.disable_inbound_email(enabled)
      assert disabled.inbound_email_token == nil
      assert disabled.inbound_email_token_hash == nil
    end
  end

  describe "get_company_by_inbound_email_token/1" do
    test "returns the company matching the plaintext token" do
      company = insert(:company)
      {:ok, enabled} = Companies.enable_inbound_email(company)

      found = Companies.get_company_by_inbound_email_token(enabled.inbound_email_token)
      assert found.id == company.id
    end

    test "returns nil for unknown token" do
      assert Companies.get_company_by_inbound_email_token("abcd1234") == nil
    end

    test "returns nil for nil token" do
      assert Companies.get_company_by_inbound_email_token(nil) == nil
    end
  end

  describe "update_inbound_email_settings/2" do
    test "updates allowed sender domain and cc email" do
      company = insert(:company)

      assert {:ok, updated} =
               Companies.update_inbound_email_settings(company, %{
                 inbound_allowed_sender_domain: "appunite.com",
                 inbound_cc_email: "invoices@appunite.com"
               })

      assert updated.inbound_allowed_sender_domain == "appunite.com"
      assert updated.inbound_cc_email == "invoices@appunite.com"
    end

    test "allows clearing settings with nil" do
      company =
        insert(:company,
          inbound_allowed_sender_domain: "appunite.com",
          inbound_cc_email: "invoices@appunite.com"
        )

      assert {:ok, updated} =
               Companies.update_inbound_email_settings(company, %{
                 inbound_allowed_sender_domain: nil,
                 inbound_cc_email: nil
               })

      assert updated.inbound_allowed_sender_domain == nil
      assert updated.inbound_cc_email == nil
    end

    test "rejects invalid domain format" do
      company = insert(:company)

      assert {:error, changeset} =
               Companies.update_inbound_email_settings(company, %{
                 inbound_allowed_sender_domain: "not a domain!"
               })

      assert "must be a valid domain (e.g. appunite.com)" in errors_on(changeset).inbound_allowed_sender_domain
    end

    test "rejects invalid email format" do
      company = insert(:company)

      assert {:error, changeset} =
               Companies.update_inbound_email_settings(company, %{
                 inbound_cc_email: "not-an-email"
               })

      assert "must be a valid email address" in errors_on(changeset).inbound_cc_email
    end
  end

  describe "authorize/3" do
    test "returns {:ok, membership} when user has required role" do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      assert {:ok, %Membership{role: :owner}} =
               Companies.authorize(user.id, company.id, [:owner])
    end

    test "returns {:error, :unauthorized} when user has wrong role" do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :reviewer)

      assert {:error, :unauthorized} =
               Companies.authorize(user.id, company.id, [:owner])
    end

    test "returns {:error, :unauthorized} when user has no membership" do
      user = insert(:user)
      company = insert(:company)

      assert {:error, :unauthorized} =
               Companies.authorize(user.id, company.id, [:owner])
    end
  end
end
