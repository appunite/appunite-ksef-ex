defmodule KsefHub.Accounts.UserTokenTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Accounts.UserToken

  describe "build_session_token/1" do
    test "returns a token and a user token struct" do
      user = insert(:user)
      {token, user_token} = UserToken.build_session_token(user)

      assert is_binary(token)
      assert byte_size(token) == 32
      assert user_token.context == "session"
      assert user_token.user_id == user.id
      assert user_token.token != token
    end

    test "token is hashed in the struct" do
      user = insert(:user)
      {token, user_token} = UserToken.build_session_token(user)

      assert user_token.token == :crypto.hash(:sha256, token)
    end
  end

  describe "verify_session_token_query/1" do
    test "returns a query that finds the user by token" do
      user = insert(:user)
      {token, user_token} = UserToken.build_session_token(user)
      {:ok, _} = Repo.insert(user_token)

      assert {:ok, query} = UserToken.verify_session_token_query(token)
      assert Repo.one(query).id == user.id
    end

    test "does not return expired tokens" do
      user = insert(:user)
      {token, user_token} = UserToken.build_session_token(user)

      {:ok, _} =
        Repo.insert(%{user_token | inserted_at: ~N[2020-01-01 00:00:00]})

      assert {:ok, query} = UserToken.verify_session_token_query(token)
      refute Repo.one(query)
    end
  end

  describe "build_email_token/2" do
    test "builds a token for confirm context" do
      user = insert(:user)
      {token, user_token} = UserToken.build_email_token(user, "confirm")

      assert is_binary(token)
      assert user_token.context == "confirm"
      assert user_token.sent_to == user.email
      assert user_token.user_id == user.id
    end

    test "builds a token for reset_password context" do
      user = insert(:user)
      {token, user_token} = UserToken.build_email_token(user, "reset_password")

      assert user_token.context == "reset_password"
      assert user_token.sent_to == user.email
      assert is_binary(token)
    end
  end

  describe "verify_email_token_query/2" do
    test "returns a query that finds the user by confirm token" do
      user = insert(:user)
      {token, user_token} = UserToken.build_email_token(user, "confirm")
      {:ok, _} = Repo.insert(user_token)

      encoded = Base.url_encode64(token, padding: false)
      assert {:ok, query} = UserToken.verify_email_token_query(encoded, "confirm")
      assert Repo.one(query).id == user.id
    end

    test "does not return expired confirm tokens (> 3 days)" do
      user = insert(:user)
      {token, user_token} = UserToken.build_email_token(user, "confirm")

      {:ok, _} =
        Repo.insert(%{user_token | inserted_at: ~N[2020-01-01 00:00:00]})

      encoded = Base.url_encode64(token, padding: false)
      assert {:ok, query} = UserToken.verify_email_token_query(encoded, "confirm")
      refute Repo.one(query)
    end

    test "does not return expired reset_password tokens (> 1 day)" do
      user = insert(:user)
      {token, user_token} = UserToken.build_email_token(user, "reset_password")

      {:ok, _} =
        Repo.insert(%{user_token | inserted_at: ~N[2020-01-01 00:00:00]})

      encoded = Base.url_encode64(token, padding: false)
      assert {:ok, query} = UserToken.verify_email_token_query(encoded, "reset_password")
      refute Repo.one(query)
    end

    test "returns error for invalid base64 token" do
      assert :error = UserToken.verify_email_token_query("not-valid-base64!!!", "confirm")
    end
  end

  describe "by_user_and_contexts_query/2" do
    test "returns tokens for given user and contexts" do
      user = insert(:user)
      {_token, user_token} = UserToken.build_session_token(user)
      {:ok, _} = Repo.insert(user_token)

      query = UserToken.by_user_and_contexts_query(user, ["session"])
      assert Repo.one(query)
    end

    test "returns all tokens for :all contexts" do
      user = insert(:user)
      {_token, session_token} = UserToken.build_session_token(user)
      {:ok, _} = Repo.insert(session_token)
      {_token, email_token} = UserToken.build_email_token(user, "confirm")
      {:ok, _} = Repo.insert(email_token)

      query = UserToken.by_user_and_contexts_query(user, :all)
      assert length(Repo.all(query)) == 2
    end
  end
end
