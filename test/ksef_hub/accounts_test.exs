defmodule KsefHub.AccountsTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Accounts.{ApiToken, User}

  setup do
    Accounts.clear_allowed_emails_cache()
    :ok
  end

  defp create_user do
    insert(:user, google_uid: "uid-#{System.unique_integer([:positive])}")
  end

  defp create_api_token(user \\ nil, attrs \\ %{}) do
    user = user || create_user()
    {:ok, result} = Accounts.create_api_token(user.id, Map.merge(%{name: "Test Token"}, attrs))
    result
  end

  describe "users" do
    test "find_or_create_user/1 creates a new user" do
      assert {:ok, %User{} = user} =
               Accounts.find_or_create_user(%{
                 uid: "google-123",
                 email: "test@example.com",
                 name: "Test User",
                 avatar_url: "https://example.com/avatar.png"
               })

      assert user.email == "test@example.com"
      assert user.google_uid == "google-123"
      assert user.name == "Test User"
    end

    test "find_or_create_user/1 returns existing user" do
      {:ok, original} =
        Accounts.find_or_create_user(%{
          uid: "google-456",
          email: "existing@example.com",
          name: "Existing User"
        })

      {:ok, found} =
        Accounts.find_or_create_user(%{
          uid: "google-456",
          email: "existing@example.com",
          name: "Existing User"
        })

      assert original.id == found.id
    end

    test "get_user_by_email/1 returns user" do
      user = insert(:user, email: "find@example.com")

      assert Accounts.get_user_by_email("find@example.com").id == user.id
      assert Accounts.get_user_by_email("missing@example.com") == nil
    end

    test "allowed_email?/1 checks against configured allowlist" do
      assert Accounts.allowed_email?("test@example.com")
      assert Accounts.allowed_email?("TEST@EXAMPLE.COM")
      assert Accounts.allowed_email?("admin@example.com")
      refute Accounts.allowed_email?("unauthorized@example.com")
    end

    test "find_or_create_user/1 handles concurrent insert gracefully" do
      # Pre-insert a user, then call find_or_create_user with same uid
      # This simulates the race where the user was inserted between
      # get_user_by_google_uid returning nil and Repo.insert
      user = insert(:user, google_uid: "race-uid", email: "race@example.com")

      assert {:ok, found} =
               Accounts.find_or_create_user(%{
                 uid: "race-uid",
                 email: "race@example.com"
               })

      assert found.id == user.id
    end
  end

  describe "api_tokens" do
    test "create_api_token/2 returns plaintext token and persisted record" do
      %{token: token, api_token: api_token} = create_api_token(nil, %{name: "My Token"})

      assert is_binary(token)
      assert String.length(token) > 20
      assert api_token.name == "My Token"
      assert api_token.token_prefix == String.slice(token, 0, 8)
      assert api_token.is_active == true
      assert api_token.request_count == 0
    end

    test "validate_api_token/1 validates a correct token" do
      %{token: token, api_token: original} = create_api_token()

      assert {:ok, %ApiToken{} = found} = Accounts.validate_api_token(token)
      assert found.id == original.id
    end

    test "validate_api_token/1 rejects invalid token" do
      assert {:error, :invalid} = Accounts.validate_api_token("bogus-token")
    end

    test "validate_api_token/1 accepts non-expired token" do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      %{token: token} = create_api_token(nil, %{expires_at: future})

      assert {:ok, %ApiToken{}} = Accounts.validate_api_token(token)
    end

    test "validate_api_token/1 rejects expired token" do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      %{token: token} = create_api_token(nil, %{expires_at: past})

      assert {:error, :expired} = Accounts.validate_api_token(token)
    end

    test "validate_api_token/1 accepts token with no expiry" do
      %{token: token} = create_api_token()

      assert {:ok, %ApiToken{expires_at: nil}} = Accounts.validate_api_token(token)
    end

    test "validate_api_token/1 rejects revoked token" do
      user = create_user()
      %{token: token, api_token: api_token} = create_api_token(user)
      {:ok, _} = Accounts.revoke_api_token(user.id, api_token.id)

      assert {:error, :invalid} = Accounts.validate_api_token(token)
    end

    test "revoke_api_token/2 deactivates a token" do
      user = create_user()
      %{api_token: api_token} = create_api_token(user)

      assert {:ok, revoked} = Accounts.revoke_api_token(user.id, api_token.id)
      assert revoked.is_active == false
    end

    test "revoke_api_token/2 rejects token owned by another user" do
      user1 = create_user()
      user2 = create_user()
      %{api_token: api_token} = create_api_token(user1)

      assert {:error, :not_found} = Accounts.revoke_api_token(user2.id, api_token.id)
    end

    test "list_api_tokens/1 returns only tokens for the given user" do
      user1 = create_user()
      user2 = create_user()
      create_api_token(user1, %{name: "User1 Token"})
      create_api_token(user2, %{name: "User2 Token"})

      tokens = Accounts.list_api_tokens(user1.id)
      assert length(tokens) == 1
      assert hd(tokens).name == "User1 Token"
      assert Enum.all?(tokens, &(&1.token_hash == "**redacted**"))
    end

    test "track_token_usage/1 returns error for non-existent token" do
      assert {:error, :not_found} = Accounts.track_token_usage(Ecto.UUID.generate())
    end

    test "track_token_usage/1 increments count and updates timestamp" do
      %{api_token: api_token} = create_api_token()

      assert api_token.request_count == 0
      assert api_token.last_used_at == nil

      :ok = Accounts.track_token_usage(api_token.id)

      updated = Repo.get!(ApiToken, api_token.id)
      assert updated.request_count == 1
      assert updated.last_used_at != nil
    end
  end
end
