defmodule KsefHub.Credentials.CertificateInfo.Behaviour do
  @moduledoc """
  Behaviour for extracting metadata (subject, expiry) from a PKCS12 certificate.
  """

  @doc """
  Extracts the subject (CN, O, etc.) and expiry date from a PKCS12 binary.

  ## Parameters

    * `p12_data` — raw PKCS12 binary data
    * `password` — password protecting the PKCS12 file

  Returns `{:ok, %{subject: String.t(), expires_at: Date.t()}}` on success,
  or `{:error, term()}` on failure.
  """
  @callback extract(p12_data :: binary(), password :: String.t()) ::
              {:ok, %{subject: String.t(), expires_at: Date.t()}} | {:error, term()}
end
