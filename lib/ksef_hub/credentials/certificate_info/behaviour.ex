defmodule KsefHub.Credentials.CertificateInfo.Behaviour do
  @moduledoc """
  Behaviour for extracting metadata (subject, expiry) from a PKCS12 certificate.
  """

  @doc """
  Extracts metadata from a PKCS12 binary.

  ## Parameters

    * `p12_data` — raw PKCS12 binary data
    * `password` — password protecting the PKCS12 file

  Returns `{:ok, info}` on success where info contains:
    * `subject` — formatted subject string (CN, O, SERIALNUMBER, etc.)
    * `not_before` — certificate validity start date
    * `expires_at` — certificate validity end date

  Returns `{:error, term()}` on failure.
  """
  @callback extract(p12_data :: binary(), password :: String.t()) ::
              {:ok, %{subject: String.t(), not_before: Date.t(), expires_at: Date.t()}}
              | {:error, term()}
end
