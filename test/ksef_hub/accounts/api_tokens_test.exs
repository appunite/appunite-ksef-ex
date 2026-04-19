defmodule KsefHub.Accounts.ApiTokensTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Accounts.ApiToken

  defp create_user do
    insert(:user, google_uid: "uid-#{System.unique_integer([:positive])}")
  end

  defp create_owner_with_company do
    user = create_user()
    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)
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

    test "create_api_token/3 allows reviewer role" do
      user = create_user()
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :approver)

      assert {:ok, %{token: _, api_token: api_token}} =
               Accounts.create_api_token(user.id, company.id, %{name: "Reviewer Token"})

      assert api_token.name == "Reviewer Token"
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
      insert(:membership, user: user, company: company2, role: :owner)

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
      insert(:membership, user: user2, company: company, role: :owner)

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
      insert(:membership, user: user, company: company2, role: :owner)

      %{api_token: api_token} = create_company_api_token(user, company1)

      assert {:error, :not_found} =
               Accounts.revoke_api_token(user.id, company2.id, api_token.id)
    end

    test "revoke_api_token/3 rejects another user's token" do
      {user1, company} = create_owner_with_company()
      user2 = create_user()
      insert(:membership, user: user2, company: company, role: :owner)

      %{api_token: api_token} = create_company_api_token(user1, company)

      assert {:error, :not_found} =
               Accounts.revoke_api_token(user2.id, company.id, api_token.id)
    end

    test "revoke_api_token/3 allows reviewer role" do
      user = create_user()
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :approver)

      token = insert(:api_token, created_by: user, company: company)

      assert {:ok, revoked} = Accounts.revoke_api_token(user.id, company.id, token.id)
      assert revoked.is_active == false
    end

    test "revoke_api_token/3 rejects user with no membership" do
      user = create_user()
      company = insert(:company)

      token = insert(:api_token, created_by: user, company: company)

      assert {:error, :unauthorized} =
               Accounts.revoke_api_token(user.id, company.id, token.id)
    end
  end
end
