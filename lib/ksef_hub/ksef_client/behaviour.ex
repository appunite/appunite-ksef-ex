defmodule KsefHub.KsefClient.Behaviour do
  @moduledoc """
  Behaviour for KSeF API client (v2). Implementations: Live (HTTP) and Mock (test).
  """

  @callback get_challenge() ::
              {:ok, %{challenge: String.t(), timestamp: String.t()}} | {:error, term()}

  @callback authenticate_xades(signed_xml :: String.t()) ::
              {:ok,
               %{
                 reference_number: String.t(),
                 auth_token: String.t(),
                 auth_token_valid_until: DateTime.t() | nil
               }}
              | {:error, term()}

  @callback poll_auth_status(reference_number :: String.t(), auth_token :: String.t()) ::
              {:ok, :success} | {:ok, :pending} | {:error, term()}

  @callback redeem_tokens(auth_token :: String.t()) ::
              {:ok,
               %{
                 access_token: String.t(),
                 refresh_token: String.t(),
                 access_valid_until: DateTime.t(),
                 refresh_valid_until: DateTime.t()
               }}
              | {:error, term()}

  @callback refresh_access_token(refresh_token :: String.t()) ::
              {:ok, %{access_token: String.t(), valid_until: DateTime.t()}} | {:error, term()}

  @callback query_invoice_metadata(
              access_token :: String.t(),
              filters :: map(),
              opts :: keyword()
            ) ::
              {:ok, %{invoices: list(), has_more: boolean(), is_truncated: boolean()}}
              | {:error, term()}

  @callback download_invoice(access_token :: String.t(), ksef_number :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @callback terminate_session(token :: String.t()) :: :ok | {:error, term()}
end
