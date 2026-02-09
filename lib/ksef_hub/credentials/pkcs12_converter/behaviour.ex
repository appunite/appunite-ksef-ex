defmodule KsefHub.Credentials.Pkcs12Converter.Behaviour do
  @moduledoc """
  Behaviour for converting a PEM private key + certificate to PKCS12 format.
  """

  @doc """
  Converts a PEM-encoded private key and certificate to a PKCS12 bundle.

  Returns the PKCS12 binary data and the generated export password.

  ## Parameters

    * `key_data` — PEM-encoded private key (may be encrypted)
    * `crt_data` — PEM-encoded certificate
    * `key_passphrase` — passphrase for the private key, or `nil` if unencrypted

  """
  @callback convert(
              key_data :: binary(),
              crt_data :: binary(),
              key_passphrase :: String.t() | nil
            ) :: {:ok, %{p12_data: binary(), p12_password: String.t()}} | {:error, term()}
end
