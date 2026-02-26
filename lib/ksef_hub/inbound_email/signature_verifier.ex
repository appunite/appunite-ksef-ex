defmodule KsefHub.InboundEmail.SignatureVerifier do
  @moduledoc """
  Verifies Mailgun webhook signatures using HMAC-SHA256.

  Mailgun signs webhooks with: HMAC-SHA256(signing_key, timestamp + token).
  The signature is hex-encoded and compared in constant time.
  """

  @doc """
  Verifies a Mailgun webhook signature.

  Returns `:ok` if valid, `{:error, :invalid_signature}` otherwise.
  Uses constant-time comparison to prevent timing attacks.
  """
  @spec verify(String.t() | nil, String.t() | nil, String.t() | nil, String.t()) ::
          :ok | {:error, :invalid_signature}
  def verify(timestamp, token, signature, signing_key)
      when is_binary(timestamp) and is_binary(token) and is_binary(signature) and
             signature != "" do
    expected =
      :crypto.mac(:hmac, :sha256, signing_key, "#{timestamp}#{token}")
      |> Base.encode16(case: :lower)

    if Plug.Crypto.secure_compare(expected, signature) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  def verify(_timestamp, _token, _signature, _signing_key) do
    {:error, :invalid_signature}
  end
end
