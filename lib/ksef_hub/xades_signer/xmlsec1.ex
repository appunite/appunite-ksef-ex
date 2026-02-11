defmodule KsefHub.XadesSigner.Xmlsec1 do
  @moduledoc """
  Production XADES signer using xmlsec1 CLI.
  Only called during initial auth and re-auth (~every 48 days).
  Uses secure temp files with 0600 permissions, cleaned up after use.
  """

  @behaviour KsefHub.XadesSigner.Behaviour

  require Logger

  alias KsefHub.SecureTemp
  alias KsefHub.XadesSigner.AuthTokenRequest

  @impl true
  def sign_challenge(challenge, nip, certificate_data, certificate_password) do
    xml_template = build_auth_token_request(challenge, nip)

    cert_path = SecureTemp.write(certificate_data, "cert.p12")
    password_path = SecureTemp.write(certificate_password, "password.txt")
    xml_path = SecureTemp.write(xml_template, "request.xml")
    signed_path = SecureTemp.path("signed.xml")

    try do
      args = [
        "--sign",
        "--pkcs12",
        cert_path,
        "--pwd-file",
        password_path,
        "--output",
        signed_path,
        xml_path
      ]

      task =
        Task.async(fn ->
          try do
            System.cmd("xmlsec1", args, stderr_to_stdout: true)
          rescue
            e in ErlangError ->
              {:error, e}
          end
        end)

      case Task.yield(task, 30_000) || Task.shutdown(task, :brutal_kill) do
        {:ok, {_output, 0}} ->
          {:ok, File.read!(signed_path)}

        {:ok, {:error, %ErlangError{original: :enoent}}} ->
          Logger.error(
            "xmlsec1 not found. Install it: brew install xmlsec1 (macOS) or apt-get install xmlsec1 (Linux)"
          )

          {:error, {:xmlsec1_not_found, "xmlsec1 binary not found in PATH"}}

        {:ok, {:error, %ErlangError{original: reason}}} ->
          Logger.error("xmlsec1 failed to start: #{inspect(reason)}")
          {:error, {:xmlsec1_failed, 0, inspect(reason)}}

        {:ok, {output, exit_code}} ->
          Logger.error("xmlsec1 failed (exit #{exit_code}): #{output}")
          {:error, {:xmlsec1_failed, exit_code, output}}

        nil ->
          Logger.error("xmlsec1 timed out after 30s")
          {:error, :timeout}
      end
    after
      Enum.each([cert_path, password_path, xml_path, signed_path], &SecureTemp.delete/1)
    end
  end

  @spec build_auth_token_request(String.t(), String.t()) :: String.t()
  defp build_auth_token_request(challenge, nip) do
    AuthTokenRequest.build(challenge, nip)
  end
end
