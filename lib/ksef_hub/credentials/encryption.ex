defmodule KsefHub.Credentials.Encryption do
  @moduledoc """
  AES-256-GCM encryption for certificate data and tokens.

  The encryption key is loaded from `:ksef_hub, :credential_encryption_key` (a
  base64-encoded 32-byte AES key). When not set, falls back to
  `SHA256(SECRET_KEY_BASE)` for backward compatibility.
  """

  @aad "KsefHub.Credentials.Encryption"
  @iv_bytes 12
  @tag_bytes 16

  @doc """
  Encrypts plaintext with AES-256-GCM.
  Returns `{:ok, ciphertext}` where ciphertext includes IV + tag + encrypted data.
  """
  @spec encrypt(binary()) :: {:ok, binary()}
  def encrypt(plaintext) when is_binary(plaintext) do
    key = get_encryption_key()
    iv = :crypto.strong_rand_bytes(@iv_bytes)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, @aad, @tag_bytes, true)

    {:ok, iv <> tag <> ciphertext}
  end

  @doc """
  Decrypts ciphertext encrypted with `encrypt/1`.
  Returns `{:ok, plaintext}` or `{:error, :decryption_failed}`.
  """
  @spec decrypt(binary()) :: {:ok, binary()} | {:error, :decryption_failed | :invalid_ciphertext}
  def decrypt(<<iv::binary-size(@iv_bytes), tag::binary-size(@tag_bytes), ciphertext::binary>>) do
    key = get_encryption_key()

    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false) do
      :error -> {:error, :decryption_failed}
      plaintext -> {:ok, plaintext}
    end
  end

  def decrypt(_), do: {:error, :invalid_ciphertext}

  @spec get_encryption_key() :: <<_::256>>
  defp get_encryption_key do
    case Application.get_env(:ksef_hub, :credential_encryption_key) do
      nil ->
        secret = Application.get_env(:ksef_hub, KsefHubWeb.Endpoint)[:secret_key_base]
        :crypto.hash(:sha256, secret)

      base64_key ->
        Base.decode64!(base64_key)
    end
  end
end
