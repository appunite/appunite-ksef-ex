defmodule KsefHub.XadesSigner.Xmlsec1 do
  @moduledoc """
  Production XADES signer using xmlsec1 CLI.
  Only called during initial auth and re-auth (~every 48 days).
  Uses secure temp files with 0600 permissions, cleaned up after use.
  """

  @behaviour KsefHub.XadesSigner.Behaviour

  require Logger

  @cmd_timeout 30_000

  @impl true
  def sign_challenge(challenge, nip, certificate_data, certificate_password) do
    xml_template = build_auth_token_request(challenge, nip)

    cert_path = write_secure_temp(certificate_data, "cert.p12")
    password_path = write_secure_temp(certificate_password, "password.txt")
    xml_path = write_secure_temp(xml_template, "request.xml")
    signed_path = temp_path("signed.xml")

    try do
      args = [
        "--sign",
        "--pkcs12", cert_path,
        "--pwd-file", password_path,
        "--output", signed_path,
        xml_path
      ]

      case System.cmd("xmlsec1", args, timeout: @cmd_timeout, stderr_to_stdout: true) do
        {_output, 0} ->
          {:ok, File.read!(signed_path)}

        {output, exit_code} ->
          Logger.error("xmlsec1 failed (exit #{exit_code}): #{output}")
          {:error, {:xmlsec1_failed, exit_code, output}}
      end
    after
      Enum.each([cert_path, password_path, xml_path, signed_path], &secure_delete/1)
    end
  end

  defp build_auth_token_request(challenge, nip) do
    KsefHub.XadesSigner.AuthTokenRequest.build(challenge, nip)
  end

  defp write_secure_temp(content, suffix) do
    path = temp_path(suffix)
    File.write!(path, content)
    File.chmod!(path, 0o600)
    path
  end

  defp temp_path(suffix) do
    random = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    Path.join(System.tmp_dir!(), "ksef_#{random}_#{suffix}")
  end

  defp secure_delete(path) do
    if File.exists?(path) do
      # Overwrite with zeros before deletion
      case File.stat(path) do
        {:ok, %{size: size}} when size > 0 ->
          File.write(path, :binary.copy(<<0>>, size))

        _ ->
          :ok
      end

      File.rm(path)
    end
  rescue
    _ -> :ok
  end
end
