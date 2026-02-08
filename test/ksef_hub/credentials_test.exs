defmodule KsefHub.CredentialsTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Credentials
  alias KsefHub.Credentials.Credential

  setup do
    company = insert(:company, nip: "1234567890")
    %{company: company}
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
      attrs = %{certificate_subject: "CN=Test"}

      assert {:ok, %Credential{} = cred} =
               Credentials.replace_active_credential(company.id, attrs)

      assert cred.nip == company.nip
      assert cred.company_id == company.id
    end

    test "deactivates existing active credential", %{company: company} do
      old = insert(:credential, company: company, nip: company.nip)

      {:ok, new} =
        Credentials.replace_active_credential(company.id, %{certificate_subject: "CN=New"})

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
end
