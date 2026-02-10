defmodule KsefHub.Accounts.UserTest do
  use KsefHub.DataCase, async: true

  alias KsefHub.Accounts.User

  describe "registration_changeset/2" do
    test "valid attrs produce a valid changeset" do
      attrs = %{email: "user@example.com", password: "valid_password123"}
      changeset = User.registration_changeset(%User{}, attrs)
      assert changeset.valid?
    end

    test "requires email" do
      changeset = User.registration_changeset(%User{}, %{password: "valid_password123"})
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires password" do
      changeset = User.registration_changeset(%User{}, %{email: "user@example.com"})
      assert %{password: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email format" do
      changeset =
        User.registration_changeset(%User{}, %{email: "nope", password: "valid_password123"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates password min length (12 chars)" do
      changeset = User.registration_changeset(%User{}, %{email: "u@e.com", password: "short"})
      assert %{password: ["should be at least 12 character(s)"]} = errors_on(changeset)
    end

    test "validates password max length (72 chars)" do
      long_pass = String.duplicate("a", 73)
      changeset = User.registration_changeset(%User{}, %{email: "u@e.com", password: long_pass})
      assert %{password: ["should be at most 72 character(s)"]} = errors_on(changeset)
    end

    test "hashes the password with bcrypt" do
      attrs = %{email: "user@example.com", password: "valid_password123"}
      changeset = User.registration_changeset(%User{}, attrs)
      assert changeset.changes.hashed_password
      assert String.starts_with?(changeset.changes.hashed_password, "$2b$")
      refute Map.has_key?(changeset.changes, :password)
    end

    test "downcases and trims the email" do
      attrs = %{email: " USER@EXAMPLE.COM ", password: "valid_password123"}
      changeset = User.registration_changeset(%User{}, attrs)
      assert changeset.changes.email == "user@example.com"
    end

    test "does not accept confirmed_at or hashed_password (mass-assignment)" do
      attrs = %{
        email: "user@example.com",
        password: "valid_password123",
        confirmed_at: ~U[2025-01-01 00:00:00Z],
        hashed_password: "injected-hash"
      }

      changeset = User.registration_changeset(%User{}, attrs)
      refute Map.has_key?(changeset.changes, :confirmed_at)
      # hashed_password comes from password hashing, not direct input
      assert String.starts_with?(changeset.changes.hashed_password, "$2b$")
    end

    test "unique constraint on email" do
      attrs = %{email: "dup@example.com", password: "valid_password123"}
      {:ok, _} = Repo.insert(User.registration_changeset(%User{}, attrs))

      {:error, changeset} =
        Repo.insert(User.registration_changeset(%User{}, attrs))

      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "password_changeset/2" do
    test "valid password produces valid changeset" do
      changeset = User.password_changeset(%User{}, %{password: "new_password1234"})
      assert changeset.valid?
    end

    test "validates password min length" do
      changeset = User.password_changeset(%User{}, %{password: "short"})
      assert %{password: ["should be at least 12 character(s)"]} = errors_on(changeset)
    end

    test "hashes the password" do
      changeset = User.password_changeset(%User{}, %{password: "new_password1234"})
      assert changeset.changes.hashed_password
      refute Map.has_key?(changeset.changes, :password)
    end
  end

  describe "confirm_changeset/1" do
    test "sets confirmed_at" do
      changeset = User.confirm_changeset(%User{})
      assert changeset.changes.confirmed_at
    end
  end

  describe "valid_password?/2" do
    test "returns true for correct password" do
      hashed = Bcrypt.hash_pwd_salt("correct_password1")
      user = %User{hashed_password: hashed}
      assert User.valid_password?(user, "correct_password1")
    end

    test "returns false for wrong password" do
      hashed = Bcrypt.hash_pwd_salt("correct_password1")
      user = %User{hashed_password: hashed}
      refute User.valid_password?(user, "wrong_password123")
    end

    test "returns false when hashed_password is nil" do
      user = %User{hashed_password: nil}
      refute User.valid_password?(user, "any_password1234")
    end
  end
end
