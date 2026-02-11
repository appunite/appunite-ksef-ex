defmodule KsefHub.AccountsTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Accounts.ApiToken
  alias KsefHub.Accounts.UserToken

  defp create_user do
    insert(:user, google_uid: "uid-#{System.unique_integer([:positive])}")
  end

  defp create_owner_with_company do
    user = create_user()
    company = insert(:company)
    insert(:membership, user: user, company: company, role: "owner")
    {user, company}
  end

  defp create_api_token(user \\ nil, attrs \\ %{}) do
    user = user || create_user()
    {:ok, result} = Accounts.create_api_token(user.id, Map.merge(%{name: "Test Token"}, attrs))
    result
  end

  defp create_company_api_token(user, company, attrs \\ %{}) do
    {:ok, result} =
      Accounts.create_api_token(user.id, company.id, Map.merge(%{name: "Test Token"}, attrs))

    result
  end

  describe "users" do
    test "get_user_by_email/1 returns user" do
      user = insert(:user, email: "find@example.com")

      assert Accounts.get_user_by_email("find@example.com").id == user.id
      assert Accounts.get_user_by_email("missing@example.com") == nil
    end
  end

  describe "register_user/1" do
    test "creates user with email and password" do
      assert {:ok, user} =
               Accounts.register_user(%{email: "new@example.com", password: "valid_password123"})

      assert user.email == "new@example.com"
      assert user.hashed_password
      refute user.confirmed_at
    end

    test "returns error with invalid data" do
      assert {:error, changeset} = Accounts.register_user(%{email: "bad", password: "short"})
      assert %{email: _, password: _} = errors_on(changeset)
    end

    test "returns error with duplicate email" do
      {:ok, _} =
        Accounts.register_user(%{email: "dup@example.com", password: "valid_password123"})

      assert {:error, changeset} =
               Accounts.register_user(%{email: "dup@example.com", password: "valid_password123"})

      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "returns user for correct credentials" do
      {:ok, user} =
        Accounts.register_user(%{email: "auth@example.com", password: "valid_password123"})

      assert found =
               Accounts.get_user_by_email_and_password("auth@example.com", "valid_password123")

      assert found.id == user.id
    end

    test "returns nil for wrong password" do
      {:ok, _} =
        Accounts.register_user(%{email: "auth2@example.com", password: "valid_password123"})

      refute Accounts.get_user_by_email_and_password("auth2@example.com", "wrong_password1234")
    end

    test "returns nil for non-existent email" do
      refute Accounts.get_user_by_email_and_password("ghost@example.com", "valid_password123")
    end
  end

  describe "get_or_create_google_user/1" do
    test "creates new user for new Google UID" do
      assert {:ok, user} =
               Accounts.get_or_create_google_user(%{
                 uid: "new-google-uid",
                 email: "google@example.com",
                 name: "Google User"
               })

      assert user.google_uid == "new-google-uid"
      assert user.email == "google@example.com"
    end

    test "returns existing user for known Google UID" do
      {:ok, original} =
        Accounts.get_or_create_google_user(%{
          uid: "known-uid",
          email: "known@example.com",
          name: "Known User"
        })

      {:ok, found} =
        Accounts.get_or_create_google_user(%{
          uid: "known-uid",
          email: "known@example.com"
        })

      assert original.id == found.id
    end

    test "links Google UID to existing email user" do
      {:ok, email_user} =
        Accounts.register_user(%{email: "link@example.com", password: "valid_password123"})

      {:ok, linked} =
        Accounts.get_or_create_google_user(%{
          uid: "link-google-uid",
          email: "link@example.com",
          name: "Linked User"
        })

      assert linked.id == email_user.id
      assert linked.google_uid == "link-google-uid"
      assert linked.name == "Linked User"
    end
  end

  describe "session tokens" do
    test "generate_user_session_token/1 creates a token" do
      user = create_user()
      token = Accounts.generate_user_session_token(user)

      assert is_binary(token)
      assert byte_size(token) == 32
    end

    test "get_user_by_session_token/1 retrieves user" do
      user = create_user()
      token = Accounts.generate_user_session_token(user)

      assert found = Accounts.get_user_by_session_token(token)
      assert found.id == user.id
    end

    test "get_user_by_session_token/1 returns nil for invalid token" do
      refute Accounts.get_user_by_session_token(:crypto.strong_rand_bytes(32))
    end

    test "delete_user_session_token/1 removes token" do
      user = create_user()
      token = Accounts.generate_user_session_token(user)

      assert Accounts.get_user_by_session_token(token)
      :ok = Accounts.delete_user_session_token(token)
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "confirmation" do
    test "deliver_user_confirmation_instructions/2 sends email" do
      {:ok, user} =
        Accounts.register_user(%{email: "confirm@example.com", password: "valid_password123"})

      assert {:ok, _email} =
               Accounts.deliver_user_confirmation_instructions(user, &"/verify/#{&1}")
    end

    test "deliver_user_confirmation_instructions/2 rejects already confirmed" do
      {:ok, user} =
        Accounts.register_user(%{email: "conf2@example.com", password: "valid_password123"})

      user = %{user | confirmed_at: DateTime.utc_now()}

      assert {:error, :already_confirmed} =
               Accounts.deliver_user_confirmation_instructions(user, &"/verify/#{&1}")
    end

    test "confirm_user/1 confirms user by token" do
      {:ok, user} =
        Accounts.register_user(%{email: "conf3@example.com", password: "valid_password123"})

      {encoded_token, _} =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      assert {:ok, confirmed} = Accounts.confirm_user(encoded_token)
      assert confirmed.confirmed_at
    end

    test "confirm_user/1 returns error for invalid token" do
      assert :error = Accounts.confirm_user("invalid-token")
    end
  end

  describe "password reset" do
    setup do
      {:ok, user} =
        Accounts.register_user(%{email: "reset@example.com", password: "valid_password123"})

      %{user: user}
    end

    test "deliver_user_reset_password_instructions/2 sends email", %{user: user} do
      assert {:ok, _email} =
               Accounts.deliver_user_reset_password_instructions(user, &"/reset/#{&1}")
    end

    test "get_user_by_reset_password_token/1 returns user", %{user: user} do
      {encoded_token, _} =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      assert found = Accounts.get_user_by_reset_password_token(encoded_token)
      assert found.id == user.id
    end

    test "get_user_by_reset_password_token/1 returns nil for invalid token" do
      refute Accounts.get_user_by_reset_password_token("invalid-token")
    end

    test "reset_user_password/2 updates password", %{user: user} do
      assert {:ok, updated} =
               Accounts.reset_user_password(user, %{password: "new_password12345"})

      assert Accounts.get_user_by_email_and_password("reset@example.com", "new_password12345")
      assert updated.id == user.id
    end

    test "reset_user_password/2 deletes all tokens", %{user: user} do
      _token = Accounts.generate_user_session_token(user)
      {:ok, _} = Accounts.reset_user_password(user, %{password: "new_password12345"})

      refute Repo.one(UserToken.by_user_and_contexts_query(user, :all))
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

  describe "company-scoped api_tokens" do
    test "create_api_token/3 creates token scoped to company for owner" do
      {user, company} = create_owner_with_company()

      assert {:ok, %{token: token, api_token: api_token}} =
               Accounts.create_api_token(user.id, company.id, %{name: "Company Token"})

      assert is_binary(token)
      assert api_token.company_id == company.id
      assert api_token.created_by_id == user.id
      assert api_token.name == "Company Token"
    end

    test "create_api_token/3 rejects non-owner" do
      user = create_user()
      company = insert(:company)
      insert(:membership, user: user, company: company, role: "accountant")

      assert {:error, :unauthorized} =
               Accounts.create_api_token(user.id, company.id, %{name: "Nope"})
    end

    test "create_api_token/3 rejects user with no membership" do
      user = create_user()
      company = insert(:company)

      assert {:error, :unauthorized} =
               Accounts.create_api_token(user.id, company.id, %{name: "Nope"})
    end

    test "validate_api_token/1 returns token with company preloaded" do
      {user, company} = create_owner_with_company()
      %{token: plain_token} = create_company_api_token(user, company)

      assert {:ok, %ApiToken{} = found} = Accounts.validate_api_token(plain_token)
      assert found.company_id == company.id
      assert found.company.id == company.id
    end

    test "list_api_tokens/2 returns tokens scoped to user + company" do
      {user, company1} = create_owner_with_company()
      company2 = insert(:company)
      insert(:membership, user: user, company: company2, role: "owner")

      create_company_api_token(user, company1, %{name: "Company1 Token"})
      create_company_api_token(user, company2, %{name: "Company2 Token"})

      tokens = Accounts.list_api_tokens(user.id, company1.id)
      assert length(tokens) == 1
      assert hd(tokens).name == "Company1 Token"
      assert Enum.all?(tokens, &(&1.token_hash == "**redacted**"))
    end

    test "list_api_tokens/2 does not return other users' tokens for the same company" do
      {user1, company} = create_owner_with_company()
      user2 = create_user()
      insert(:membership, user: user2, company: company, role: "owner")

      create_company_api_token(user1, company, %{name: "User1 Token"})
      create_company_api_token(user2, company, %{name: "User2 Token"})

      tokens = Accounts.list_api_tokens(user1.id, company.id)
      assert length(tokens) == 1
      assert hd(tokens).name == "User1 Token"
    end

    test "revoke_api_token/3 revokes token scoped to user + company" do
      {user, company} = create_owner_with_company()
      %{api_token: api_token} = create_company_api_token(user, company)

      assert {:ok, revoked} = Accounts.revoke_api_token(user.id, company.id, api_token.id)
      assert revoked.is_active == false
    end

    test "revoke_api_token/3 rejects token from different company" do
      {user, company1} = create_owner_with_company()
      company2 = insert(:company)
      insert(:membership, user: user, company: company2, role: "owner")

      %{api_token: api_token} = create_company_api_token(user, company1)

      assert {:error, :not_found} =
               Accounts.revoke_api_token(user.id, company2.id, api_token.id)
    end

    test "revoke_api_token/3 rejects another user's token" do
      {user1, company} = create_owner_with_company()
      user2 = create_user()
      insert(:membership, user: user2, company: company, role: "owner")

      %{api_token: api_token} = create_company_api_token(user1, company)

      assert {:error, :not_found} =
               Accounts.revoke_api_token(user2.id, company.id, api_token.id)
    end

    test "revoke_api_token/3 rejects non-owner" do
      user = create_user()
      company = insert(:company)
      insert(:membership, user: user, company: company, role: "accountant")

      # Insert a token directly (bypassing owner check) to test revoke guard
      token = insert(:api_token, created_by: user, company: company)

      assert {:error, :unauthorized} =
               Accounts.revoke_api_token(user.id, company.id, token.id)
    end
  end
end
