defmodule KsefHub.Credentials.EncryptionTest do
  use ExUnit.Case, async: false

  alias KsefHub.Credentials.Encryption

  describe "encrypt/1 and decrypt/1" do
    test "round-trip encryption works" do
      plaintext = "super-secret-certificate-password"

      assert {:ok, ciphertext} = Encryption.encrypt(plaintext)
      assert ciphertext != plaintext
      assert {:ok, ^plaintext} = Encryption.decrypt(ciphertext)
    end

    test "encrypts binary data" do
      binary_data = :crypto.strong_rand_bytes(256)

      assert {:ok, ciphertext} = Encryption.encrypt(binary_data)
      assert {:ok, ^binary_data} = Encryption.decrypt(ciphertext)
    end

    test "different encryptions produce different ciphertexts (random IV)" do
      plaintext = "same-input"

      {:ok, ct1} = Encryption.encrypt(plaintext)
      {:ok, ct2} = Encryption.encrypt(plaintext)

      assert ct1 != ct2
    end

    test "returns error for invalid ciphertext" do
      assert {:error, :invalid_ciphertext} = Encryption.decrypt("too-short")
    end

    test "returns error for tampered ciphertext" do
      {:ok, ciphertext} = Encryption.encrypt("original")

      # Tamper with the ciphertext
      tampered = ciphertext <> <<0>>
      assert {:error, :decryption_failed} = Encryption.decrypt(tampered)
    end
  end

  describe "base64 encryption key" do
    setup do
      prev = Application.get_env(:ksef_hub, :credential_encryption_key)
      on_exit(fn -> Application.put_env(:ksef_hub, :credential_encryption_key, prev) end)
      :ok
    end

    test "uses base64-encoded key when configured" do
      # Derive the same key the fallback would produce, then base64-encode it
      secret = Application.get_env(:ksef_hub, KsefHubWeb.Endpoint)[:secret_key_base]
      key = :crypto.hash(:sha256, secret)
      base64_key = Base.encode64(key)

      # Encrypt with fallback (SHA256) path
      Application.delete_env(:ksef_hub, :credential_encryption_key)
      {:ok, ciphertext} = Encryption.encrypt("test-data")

      # Decrypt with explicit base64 key — same underlying key, should work
      Application.put_env(:ksef_hub, :credential_encryption_key, base64_key)
      assert {:ok, "test-data"} = Encryption.decrypt(ciphertext)
    end

    test "round-trip works with standalone base64 key" do
      key = :crypto.strong_rand_bytes(32)
      Application.put_env(:ksef_hub, :credential_encryption_key, Base.encode64(key))

      plaintext = "encrypted-with-standalone-key"
      assert {:ok, ciphertext} = Encryption.encrypt(plaintext)
      assert {:ok, ^plaintext} = Encryption.decrypt(ciphertext)
    end
  end
end
