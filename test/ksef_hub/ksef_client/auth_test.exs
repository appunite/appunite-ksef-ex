defmodule KsefHub.KsefClient.AuthTest do
  use ExUnit.Case, async: true

  import Mox

  alias KsefHub.KsefClient.Auth

  setup :verify_on_exit!

  describe "authenticate/3" do
    test "successful XADES auth flow" do
      KsefHub.KsefClient.Mock
      |> expect(:get_challenge, fn ->
        {:ok, %{challenge: "test-challenge-123", timestamp: "2025-01-15T12:00:00Z"}}
      end)

      KsefHub.XadesSigner.Mock
      |> expect(:sign_challenge, fn "test-challenge-123", "1234567890", _cert, _pass ->
        {:ok, "<SignedXML>...</SignedXML>"}
      end)

      KsefHub.KsefClient.Mock
      |> expect(:authenticate_xades, fn "<SignedXML>...</SignedXML>" ->
        {:ok, %{reference_number: "ref-123", operation_token: "op-token-456"}}
      end)

      KsefHub.KsefClient.Mock
      |> expect(:poll_auth_status, fn "ref-123", "op-token-456" ->
        {:ok, :success}
      end)

      KsefHub.KsefClient.Mock
      |> expect(:redeem_tokens, fn "op-token-456" ->
        {:ok, %{
          access_token: "access-tok",
          refresh_token: "refresh-tok",
          access_valid_until: DateTime.add(DateTime.utc_now(), 900),
          refresh_valid_until: DateTime.add(DateTime.utc_now(), 48 * 24 * 3600)
        }}
      end)

      assert {:ok, tokens} = Auth.authenticate("1234567890", "cert-data", "cert-pass")
      assert tokens.access_token == "access-tok"
      assert tokens.refresh_token == "refresh-tok"
    end

    test "handles challenge failure" do
      KsefHub.KsefClient.Mock
      |> expect(:get_challenge, fn ->
        {:error, {:ksef_error, 500, "Internal Server Error"}}
      end)

      assert {:error, {:ksef_error, 500, _}} =
               Auth.authenticate("1234567890", "cert-data", "cert-pass")
    end

    test "handles signing failure" do
      KsefHub.KsefClient.Mock
      |> expect(:get_challenge, fn ->
        {:ok, %{challenge: "challenge", timestamp: "2025-01-15T12:00:00Z"}}
      end)

      KsefHub.XadesSigner.Mock
      |> expect(:sign_challenge, fn _, _, _, _ ->
        {:error, {:xmlsec1_failed, 1, "signing error"}}
      end)

      assert {:error, {:xmlsec1_failed, 1, _}} =
               Auth.authenticate("1234567890", "cert-data", "cert-pass")
    end
  end
end
