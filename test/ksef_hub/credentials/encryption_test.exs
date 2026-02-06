defmodule KsefHub.Credentials.EncryptionTest do
  use ExUnit.Case, async: true

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
end
