defmodule KsefHub.Credentials.Pkcs12Converter.Openssl do
  @moduledoc """
  Converts a PEM private key + certificate to PKCS12 format using the `openssl` CLI.

  Uses secure temp files with `0600` permissions, cleaned up after use.
  Passes passwords via file (not CLI arguments) to avoid exposure in `ps`.
  """

  @behaviour KsefHub.Credentials.Pkcs12Converter.Behaviour

  require Logger

  alias KsefHub.SecureTemp

  @impl true
  @spec convert(binary(), binary(), String.t() | nil) ::
          {:ok, %{p12_data: binary(), p12_password: String.t()}} | {:error, term()}
  def convert(key_data, crt_data, key_passphrase) do
    p12_password = generate_password()

    key_path = SecureTemp.write(key_data, "key.pem")
    crt_path = SecureTemp.write(crt_data, "cert.pem")
    p12_path = SecureTemp.path("output.p12")
    passout_path = SecureTemp.write(p12_password, "passout.txt")
    passin_path = if key_passphrase, do: SecureTemp.write(key_passphrase, "passin.txt")

    try do
      args =
        ["pkcs12", "-export", "-inkey", key_path, "-in", crt_path, "-out", p12_path] ++
          passout_args(passout_path) ++
          passin_args(passin_path)

      case System.cmd("openssl", args, stderr_to_stdout: true) do
        {_output, 0} ->
          case File.read(p12_path) do
            {:ok, p12_data} ->
              {:ok, %{p12_data: p12_data, p12_password: p12_password}}

            {:error, reason} ->
              Logger.error("Failed to read PKCS12 output: #{inspect(reason)}")
              {:error, {:file_read_failed, reason}}
          end

        {output, exit_code} ->
          Logger.error("openssl pkcs12 failed (exit #{exit_code}): #{output}")
          {:error, {:openssl_failed, exit_code, output}}
      end
    after
      paths = [key_path, crt_path, p12_path, passout_path | List.wrap(passin_path)]
      Enum.each(paths, &SecureTemp.delete/1)
    end
  end

  @spec passout_args(String.t()) :: [String.t()]
  defp passout_args(passout_path), do: ["-passout", "file:#{passout_path}"]

  @spec passin_args(String.t() | nil) :: [String.t()]
  defp passin_args(nil), do: ["-passin", "pass:"]
  defp passin_args(passin_path), do: ["-passin", "file:#{passin_path}"]

  @spec generate_password() :: String.t()
  defp generate_password do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
