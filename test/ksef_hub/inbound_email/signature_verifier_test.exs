defmodule KsefHub.InboundEmail.SignatureVerifierTest do
  use ExUnit.Case, async: true

  alias KsefHub.InboundEmail.SignatureVerifier

  @signing_key "test-signing-key-123"

  describe "verify/3" do
    test "returns :ok for valid HMAC signature" do
      timestamp = "1234567890"
      token = "random-token-value"
      expected_signature = compute_signature(timestamp, token)

      assert :ok = SignatureVerifier.verify(timestamp, token, expected_signature, @signing_key)
    end

    test "returns {:error, :invalid_signature} for wrong signature" do
      assert {:error, :invalid_signature} =
               SignatureVerifier.verify("1234567890", "token", "bad-signature", @signing_key)
    end

    test "returns {:error, :invalid_signature} for empty signature" do
      assert {:error, :invalid_signature} =
               SignatureVerifier.verify("1234567890", "token", "", @signing_key)
    end

    test "returns {:error, :invalid_signature} for nil values" do
      assert {:error, :invalid_signature} =
               SignatureVerifier.verify(nil, nil, nil, @signing_key)
    end
  end

  defp compute_signature(timestamp, token) do
    :crypto.mac(:hmac, :sha256, @signing_key, "#{timestamp}#{token}")
    |> Base.encode16(case: :lower)
  end
end
