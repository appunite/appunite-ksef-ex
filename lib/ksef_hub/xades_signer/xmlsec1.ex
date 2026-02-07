defmodule KsefHub.XadesSigner.Xmlsec1 do
  @moduledoc """
  Production XADES signer using xmlsec1 CLI.
  Only called during initial auth and re-auth (~every 48 days).
  Uses a private per-run temp directory (mode 0700) with files at mode 0600,
  securely cleaned up after use.
  """

  @behaviour KsefHub.XadesSigner.Behaviour

  require Logger

  @cmd_timeout 30_000

  @impl true
  def sign_challenge(challenge, nip, certificate_data, certificate_password) do
    xml_template = build_auth_token_request(challenge, nip)
    tmp_dir = create_secure_tmp_dir()

    cert_path = write_secure_file(tmp_dir, "cert.p12", certificate_data)
    password_path = write_secure_file(tmp_dir, "password.txt", certificate_password)
    xml_path = write_secure_file(tmp_dir, "request.xml", xml_template)
    signed_path = Path.join(tmp_dir, "signed.xml")

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

      case System.cmd("xmlsec1", args, timeout: @cmd_timeout, stderr_to_stdout: true) do
        {_output, 0} ->
          {:ok, File.read!(signed_path)}

        {output, exit_code} ->
          Logger.error("xmlsec1 failed (exit #{exit_code}): #{output}")
          {:error, {:xmlsec1_failed, exit_code, output}}
      end
    after
      secure_delete_dir(tmp_dir)
    end
  end

  @spec build_auth_token_request(String.t(), String.t()) :: String.t()
  defp build_auth_token_request(challenge, nip) do
    KsefHub.XadesSigner.AuthTokenRequest.build(challenge, nip)
  end

  @spec create_secure_tmp_dir() :: Path.t()
  defp create_secure_tmp_dir do
    random = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    dir = Path.join(System.tmp_dir!(), "ksef_sign_#{random}")
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)
    dir
  end

  @spec write_secure_file(Path.t(), String.t(), binary()) :: Path.t()
  defp write_secure_file(dir, filename, content) do
    path = Path.join(dir, filename)
    # Create empty file with restrictive permissions before writing content
    File.touch!(path)
    File.chmod!(path, 0o600)
    File.write!(path, content)
    path
  end

  @spec secure_delete_dir(Path.t()) :: :ok
  defp secure_delete_dir(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        Enum.each(files, fn file ->
          secure_delete(Path.join(dir, file))
        end)

        File.rmdir(dir)

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  @spec secure_delete(Path.t()) :: :ok
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
