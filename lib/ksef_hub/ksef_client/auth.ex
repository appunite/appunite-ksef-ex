defmodule KsefHub.KsefClient.Auth do
  @moduledoc """
  Orchestrates the XADES authentication flow with KSeF.
  This is only needed for initial authentication and re-authentication
  when the refresh token expires (~every 48 days).
  """

  require Logger

  @poll_interval_ms 2_000
  @max_poll_attempts 30

  defp ksef_client, do: Application.get_env(:ksef_hub, :ksef_client, KsefHub.KsefClient.Live)

  defp xades_signer,
    do: Application.get_env(:ksef_hub, :xades_signer, KsefHub.XadesSigner.Xmlsec1)

  @doc """
  Performs full XADES authentication flow:
  1. Get challenge from KSeF
  2. Sign challenge with XADES (xmlsec1 + PKCS12 cert)
  3. Submit signed XML to KSeF
  4. Poll for auth completion
  5. Redeem tokens (access + refresh)

  Returns `{:ok, tokens}` or `{:error, reason}`.
  """
  def authenticate(nip, certificate_data, certificate_password) do
    with {:ok, %{challenge: challenge}} <- ksef_client().get_challenge(),
         {:ok, signed_xml} <-
           xades_signer().sign_challenge(challenge, nip, certificate_data, certificate_password),
         {:ok, %{reference_number: ref, auth_token: auth_token}} <-
           ksef_client().authenticate_xades(signed_xml),
         :ok <- poll_until_ready(ref, auth_token),
         {:ok, tokens} <- ksef_client().redeem_tokens(auth_token) do
      Logger.info("KSeF XADES authentication successful for NIP #{nip}")
      {:ok, tokens}
    else
      {:error, reason} = error ->
        Logger.error("KSeF XADES authentication failed: #{inspect(reason)}")
        error
    end
  end

  defp poll_until_ready(reference_number, auth_token, attempt \\ 0)

  defp poll_until_ready(_reference_number, _auth_token, attempt)
       when attempt >= @max_poll_attempts do
    {:error, :auth_timeout}
  end

  defp poll_until_ready(reference_number, auth_token, attempt) do
    case ksef_client().poll_auth_status(reference_number, auth_token) do
      {:ok, :success} ->
        :ok

      {:ok, :pending} ->
        Process.sleep(@poll_interval_ms)
        poll_until_ready(reference_number, auth_token, attempt + 1)

      {:error, _} = error ->
        error
    end
  end
end
