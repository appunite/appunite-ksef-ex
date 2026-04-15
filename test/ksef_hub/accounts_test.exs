defmodule KsefHub.AccountsTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Accounts.UserToken

  defp create_user do
    insert(:user, google_uid: "uid-#{System.unique_integer([:positive])}")
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

end
