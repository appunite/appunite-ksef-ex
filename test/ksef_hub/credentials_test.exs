defmodule KsefHub.CredentialsTest do
  use KsefHub.DataCase, async: true

  alias KsefHub.Credentials
  alias KsefHub.Credentials.Credential

  @valid_attrs %{
    nip: "1234567890",
    certificate_subject: "CN=Test Certificate"
  }

  defp create_credential(attrs \\ %{}) do
    {:ok, credential} = Credentials.create_credential(Map.merge(@valid_attrs, attrs))
    credential
  end

  describe "create_credential/1" do
    test "creates a credential with valid NIP" do
      assert {:ok, %Credential{} = cred} = Credentials.create_credential(@valid_attrs)
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
      create_credential()
      assert %Credential{is_active: true} = Credentials.get_active_credential()
    end

    test "returns nil when no active credential" do
      cred = create_credential()
      Credentials.deactivate_credential(cred)
      assert Credentials.get_active_credential() == nil
    end
  end

  describe "deactivate_credential/1" do
    test "sets is_active to false" do
      cred = create_credential()
      assert {:ok, %Credential{is_active: false}} = Credentials.deactivate_credential(cred)
    end
  end

  describe "update_last_sync/1" do
    test "sets last_sync_at to current time" do
      cred = create_credential()
      assert cred.last_sync_at == nil

      assert {:ok, updated} = Credentials.update_last_sync(cred)
      assert updated.last_sync_at != nil
    end
  end

  describe "store_tokens/2" do
    test "stores token information" do
      cred = create_credential()

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
      create_credential(%{nip: "1111111111"})
      create_credential(%{nip: "2222222222"})

      assert length(Credentials.list_credentials()) == 2
    end
  end
end
