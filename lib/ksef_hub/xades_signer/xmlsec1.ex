defmodule KsefHub.XadesSigner.Xmlsec1 do
  @moduledoc """
  Production XADES signer using xmlsec1 CLI.
  Only called during initial auth and re-auth (~every 48 days).
  Uses secure temp files with 0600 permissions, cleaned up after use.

  Supports both xmlsec1 < 1.3 (has --pwd-file) and >= 1.3 (only --pwd).
  """

  @behaviour KsefHub.XadesSigner.Behaviour

  require Logger

  alias KsefHub.SecureTemp
  alias KsefHub.XadesSigner.AuthTokenRequest

  @impl true
  @spec sign_challenge(String.t(), String.t(), binary(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def sign_challenge(challenge, nip, certificate_data, certificate_password) do
    xml_template = build_auth_token_request(challenge, nip)

    cert_path = SecureTemp.write(certificate_data, "cert.p12")
    xml_path = SecureTemp.write(xml_template, "request.xml")
    signed_path = SecureTemp.path("signed.xml")

    {password_args, password_path} = build_password_args(certificate_password)

    try do
      args =
        ["--sign", "--pkcs12", cert_path] ++
          password_args ++
          ["--output", signed_path, xml_path]

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
      cleanup_paths = [cert_path, xml_path, signed_path]
      cleanup_paths = if password_path, do: [password_path | cleanup_paths], else: cleanup_paths
      Enum.each(cleanup_paths, &SecureTemp.delete/1)
    end
  end

  # xmlsec1 >= 1.3 (xmlsec library 3.x) removed --pwd-file, only --pwd is available.
  # Older versions support --pwd-file for secure file-based password passing.
  @spec build_password_args(String.t()) :: {[String.t()], String.t() | nil}
  defp build_password_args(password) do
    if supports_pwd_file?() do
      path = SecureTemp.write(password, "password.txt")
      {["--pwd-file", path], path}
    else
      {["--pwd", password], nil}
    end
  end

  @spec supports_pwd_file?() :: boolean()
  defp supports_pwd_file? do
    case System.cmd("xmlsec1", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        case Regex.run(~r/xmlsec1 (\d+)\.(\d+)/, output) do
          [_, major, minor] ->
            {String.to_integer(major), String.to_integer(minor)} < {1, 3}

          _ ->
            false
        end

      _ ->
        false
    end
  rescue
    _ -> false
  end

  @spec build_auth_token_request(String.t(), String.t()) :: String.t()
  defp build_auth_token_request(challenge, nip) do
    AuthTokenRequest.build(challenge, nip)
  end
end
