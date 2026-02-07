defmodule KsefHub.Credentials.Encryption do
  @moduledoc """
  AES-256-GCM encryption for certificate data and tokens.
  Key is sourced from application config (Secret Manager in production).
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

  @spec get_encryption_key() :: binary()
  defp get_encryption_key do
    case Application.get_env(:ksef_hub, :encryption_key) do
      nil ->
        # Fallback: derive from SECRET_KEY_BASE for development
        secret = Application.get_env(:ksef_hub, KsefHubWeb.Endpoint)[:secret_key_base]
        :crypto.hash(:sha256, secret)

      key when byte_size(key) == 32 ->
        key

      base64_key when is_binary(base64_key) ->
        case Base.decode64(base64_key) do
          {:ok, decoded} when byte_size(decoded) == 32 ->
            decoded

          {:ok, decoded} ->
            raise "Encryption key has invalid size: expected 32 bytes, got #{byte_size(decoded)}"

          :error ->
            raise "Encryption key is not valid Base64"
        end
    end
  end
end
