defmodule KsefHub.CredentialsTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Credentials
  alias KsefHub.Credentials.{Credential, UserCertificate}

  setup do
    company = insert(:company, nip: "1234567890")
    user = insert(:user)
    %{company: company, user: user}
  end

  describe "create_credential/1" do
    test "creates a credential with valid NIP and company", %{company: company} do
      attrs = params_for(:credential, nip: "1234567890", company_id: company.id)
      assert {:ok, %Credential{} = cred} = Credentials.create_credential(attrs)
      assert cred.nip == "1234567890"
      assert cred.is_active == true
      assert cred.company_id == company.id
    end

    test "rejects NIP that is too short", %{company: company} do
      assert {:error, changeset} =
               Credentials.create_credential(%{nip: "12345", company_id: company.id})

      assert "must be a 10-digit NIP" in errors_on(changeset).nip
    end

    test "rejects NIP that is too long", %{company: company} do
      assert {:error, changeset} =
               Credentials.create_credential(%{nip: "12345678901", company_id: company.id})

      assert "must be a 10-digit NIP" in errors_on(changeset).nip
    end

    test "rejects NIP with non-digit characters", %{company: company} do
      assert {:error, changeset} =
               Credentials.create_credential(%{nip: "123456789a", company_id: company.id})

      assert "must be a 10-digit NIP" in errors_on(changeset).nip
    end

    test "requires NIP" do
      assert {:error, changeset} = Credentials.create_credential(%{})
      assert errors_on(changeset).nip
    end

    test "requires company_id" do
      assert {:error, changeset} = Credentials.create_credential(%{nip: "1234567890"})
      assert errors_on(changeset).company_id
    end
  end

  describe "get_active_credential/1" do
    test "returns active credential for company", %{company: company} do
      insert(:credential, company: company, nip: company.nip)

      assert %Credential{is_active: true} = Credentials.get_active_credential(company.id)
    end

    test "returns nil when no active credential for company", %{company: company} do
      cred = insert(:credential, company: company, nip: company.nip)
      Credentials.deactivate_credential(cred)
      assert Credentials.get_active_credential(company.id) == nil
    end

    test "does not return credentials from other companies", %{company: company} do
      other_company = insert(:company)
      insert(:credential, company: other_company, nip: other_company.nip)

      assert Credentials.get_active_credential(company.id) == nil
    end
  end

  describe "list_credentials/1" do
    test "returns credentials for the given company", %{company: company} do
      insert(:credential, company: company, nip: company.nip, is_active: false)

      other_company = insert(:company)
      insert(:credential, company: other_company, nip: other_company.nip)

      assert [%Credential{}] = Credentials.list_credentials(company.id)
    end
  end

  describe "list_active_credentials/0" do
    test "returns all active credentials across companies" do
      c1 = insert(:company)
      c2 = insert(:company)
      insert(:credential, company: c1, nip: c1.nip)
      insert(:credential, company: c2, nip: c2.nip)

      active = Credentials.list_active_credentials()
      assert length(active) == 2
      assert Enum.all?(active, & &1.is_active)
    end
  end

  describe "replace_active_credential/2" do
    test "creates credential with NIP from company", %{company: company} do
      assert {:ok, %Credential{} = cred} =
               Credentials.replace_active_credential(company.id, %{})

      assert cred.nip == company.nip
      assert cred.company_id == company.id
    end

    test "deactivates existing active credential", %{company: company} do
      old = insert(:credential, company: company, nip: company.nip)

      {:ok, new} = Credentials.replace_active_credential(company.id, %{})

      assert Credentials.get_credential!(old.id).is_active == false
      assert new.is_active == true
    end
  end

  describe "deactivate_credential/1" do
    test "sets is_active to false", %{company: company} do
      cred = insert(:credential, company: company, nip: company.nip)
      assert {:ok, %Credential{is_active: false}} = Credentials.deactivate_credential(cred)
    end
  end

  describe "update_last_sync/1" do
    test "sets last_sync_at to current time", %{company: company} do
      cred = insert(:credential, company: company, nip: company.nip)
      assert cred.last_sync_at == nil

      assert {:ok, updated} = Credentials.update_last_sync(cred)
      assert updated.last_sync_at != nil
    end
  end

  describe "store_tokens/2" do
    test "stores token information", %{company: company} do
      cred = insert(:credential, company: company, nip: company.nip)

      assert {:ok, updated} =
               Credentials.store_tokens(cred, %{
                 access_token_encrypted: "encrypted-access-123",
                 access_token_expires_at: DateTime.utc_now()
               })

      assert updated.access_token_encrypted == "encrypted-access-123"
    end
  end

  # ---------------------------------------------------------------------------
  # User Certificates
  # ---------------------------------------------------------------------------

  describe "get_active_user_certificate/1" do
    test "returns the active certificate for a user", %{user: user} do
      insert(:user_certificate, user: user, is_active: true)

      assert %UserCertificate{is_active: true} =
               Credentials.get_active_user_certificate(user.id)
    end

    test "returns nil when user has no active certificate", %{user: user} do
      insert(:user_certificate, user: user, is_active: false)

      assert is_nil(Credentials.get_active_user_certificate(user.id))
    end

    test "returns nil when user has no certificates" do
      other_user = insert(:user)
      assert is_nil(Credentials.get_active_user_certificate(other_user.id))
    end

    test "does not return certificates from other users", %{user: user} do
      other_user = insert(:user)
      insert(:user_certificate, user: other_user, is_active: true)

      assert is_nil(Credentials.get_active_user_certificate(user.id))
    end
  end

  describe "create_user_certificate/2" do
    test "creates a certificate for the user", %{user: user} do
      attrs =
        :user_certificate
        |> params_for()
        |> Map.drop([:user_id])
        |> Map.merge(%{
          certificate_subject: "CN=Test",
          not_before: ~D[2026-01-01],
          not_after: ~D[2028-01-01],
          fingerprint: "AA:BB"
        })

      assert {:ok, %UserCertificate{} = cert} =
               Credentials.create_user_certificate(user, attrs)

      assert cert.user_id == user.id
      assert cert.certificate_subject == "CN=Test"
      assert cert.is_active == true
    end

    test "rejects if user already has an active certificate", %{user: user} do
      insert(:user_certificate, user: user, is_active: true)

      attrs =
        :user_certificate
        |> params_for()
        |> Map.drop([:user_id])

      assert {:error, changeset} = Credentials.create_user_certificate(user, attrs)
      assert %{user_id: ["already has an active certificate"]} = errors_on(changeset)
    end

    test "does not allow mass-assignment of user_id", %{user: user} do
      other_user = insert(:user)

      attrs =
        :user_certificate
        |> params_for()
        |> Map.drop([:user_id])
        |> Map.put(:user_id, other_user.id)

      assert {:ok, cert} = Credentials.create_user_certificate(user, attrs)
      assert cert.user_id == user.id
    end
  end

  describe "replace_active_user_certificate/2" do
    test "creates new active cert when no existing cert", %{user: user} do
      attrs =
        :user_certificate
        |> params_for()
        |> Map.drop([:user_id])
        |> Map.put(:certificate_subject, "CN=New")

      assert {:ok, %UserCertificate{} = cert} =
               Credentials.replace_active_user_certificate(user.id, attrs)

      assert cert.is_active == true
      assert cert.certificate_subject == "CN=New"
    end

    test "deactivates old cert and creates new one", %{user: user} do
      old = insert(:user_certificate, user: user, is_active: true)

      attrs =
        :user_certificate
        |> params_for()
        |> Map.drop([:user_id])
        |> Map.put(:certificate_subject, "CN=Replacement")

      assert {:ok, %UserCertificate{} = new_cert} =
               Credentials.replace_active_user_certificate(user.id, attrs)

      assert new_cert.is_active == true
      assert new_cert.certificate_subject == "CN=Replacement"

      old_reloaded = Repo.get!(UserCertificate, old.id)
      assert old_reloaded.is_active == false
    end

    test "returns changeset error on invalid attrs", %{user: user} do
      assert {:error, _changeset} =
               Credentials.replace_active_user_certificate(user.id, %{})
    end
  end

  describe "get_certificate_for_company/1" do
    test "returns owner's active certificate for the company", %{
      company: company,
      user: user
    } do
      insert(:membership, user: user, company: company, role: "owner")
      cert = insert(:user_certificate, user: user, is_active: true)

      result = Credentials.get_certificate_for_company(company.id)
      assert result.id == cert.id
    end

    test "returns nil when company has no owner", %{company: company} do
      assert is_nil(Credentials.get_certificate_for_company(company.id))
    end

    test "returns nil when owner has no active certificate", %{
      company: company,
      user: user
    } do
      insert(:membership, user: user, company: company, role: "owner")
      insert(:user_certificate, user: user, is_active: false)

      assert is_nil(Credentials.get_certificate_for_company(company.id))
    end

    test "does not return non-owner's certificate", %{company: company} do
      accountant = insert(:user)
      insert(:membership, user: accountant, company: company, role: "accountant")
      insert(:user_certificate, user: accountant, is_active: true)

      assert is_nil(Credentials.get_certificate_for_company(company.id))
    end

    test "does not return certificate from another company's owner" do
      other_company = insert(:company)
      other_user = insert(:user)
      insert(:membership, user: other_user, company: other_company, role: "owner")
      insert(:user_certificate, user: other_user, is_active: true)

      unrelated_company = insert(:company)
      assert is_nil(Credentials.get_certificate_for_company(unrelated_company.id))
    end
  end
end
