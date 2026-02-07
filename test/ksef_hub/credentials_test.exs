defmodule KsefHub.CredentialsTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Credentials
  alias KsefHub.Credentials.Credential

  describe "create_credential/1" do
    test "creates a credential with valid NIP" do
      attrs = params_for(:credential, nip: "1234567890")
      assert {:ok, %Credential{} = cred} = Credentials.create_credential(attrs)
      assert cred.nip == "1234567890"
      assert cred.is_active == true
    end

    test "rejects invalid NIP format" do
      assert {:error, changeset} = Credentials.create_credential(%{nip: "12345"})
      assert "must be a 10-digit NIP" in errors_on(changeset).nip
    end

    test "requires NIP" do
      assert {:error, changeset} = Credentials.create_credential(%{})
      assert errors_on(changeset).nip
    end
  end

  describe "get_active_credential/0" do
    test "returns active credential" do
      insert(:credential)
      assert %Credential{is_active: true} = Credentials.get_active_credential()
    end

    test "returns nil when no active credential" do
      cred = insert(:credential)
      Credentials.deactivate_credential(cred)
      assert Credentials.get_active_credential() == nil
    end
  end

  describe "deactivate_credential/1" do
    test "sets is_active to false" do
      cred = insert(:credential)
      assert {:ok, %Credential{is_active: false}} = Credentials.deactivate_credential(cred)
    end
  end

  describe "update_last_sync/1" do
    test "sets last_sync_at to current time" do
      cred = insert(:credential)
      assert cred.last_sync_at == nil

      assert {:ok, updated} = Credentials.update_last_sync(cred)
      assert updated.last_sync_at != nil
    end
  end

  describe "store_tokens/2" do
    test "stores token information" do
      cred = insert(:credential)

      assert {:ok, updated} =
               Credentials.store_tokens(cred, %{
                 access_token_encrypted: "encrypted-access-123",
                 access_token_expires_at: DateTime.utc_now()
               })

      assert updated.access_token_encrypted == "encrypted-access-123"
    end
  end

  describe "list_credentials/0" do
    test "returns all credentials" do
      insert(:credential)
      insert(:credential)

      assert length(Credentials.list_credentials()) == 2
    end
  end
end
