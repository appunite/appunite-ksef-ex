defmodule KsefHub.KsefClient.Authenticator do
  @moduledoc """
  Shared XADES authentication logic for workers.

  Extracts the "load cert -> decrypt -> authenticate -> store tokens" flow
  so both AuthWorker and SyncWorker can perform XADES re-authentication
  without duplicating logic.
  """

  require Logger

  alias KsefHub.Credentials
  alias KsefHub.Credentials.Encryption
  alias KsefHub.KsefClient.{Auth, TokenManager}

  @doc """
  Loads the certificate for a company, decrypts it, performs full XADES
  authentication against KSeF, and stores the resulting tokens.

  Returns `{:ok, access_token}` on success, or `{:error, reason}` on failure.
  """
  @spec authenticate_and_store(Ecto.UUID.t()) :: {:ok, String.t()} | {:error, term()}
  def authenticate_and_store(company_id) do
    with {:ok, credential} <- load_credential(company_id),
         {:ok, user_cert} <- load_certificate(company_id),
         {:ok, cert_data} <- Encryption.decrypt(user_cert.certificate_data_encrypted),
         {:ok, password} <- Encryption.decrypt(user_cert.certificate_password_encrypted),
         {:ok, tokens} <- Auth.authenticate(credential.nip, cert_data, password),
         :ok <-
           TokenManager.store_tokens(
             company_id,
             tokens.access_token,
             tokens.refresh_token,
             tokens.access_valid_until,
             tokens.refresh_valid_until
           ) do
      Logger.info("Authenticator: XADES authentication successful for company #{company_id}")
      {:ok, tokens.access_token}
    end
  end

  @spec load_credential(Ecto.UUID.t()) ::
          {:ok, Credentials.Credential.t()} | {:error, :no_credential}
  defp load_credential(company_id) do
    case Credentials.get_active_credential(company_id) do
      nil -> {:error, :no_credential}
      credential -> {:ok, credential}
    end
  end

  @spec load_certificate(Ecto.UUID.t()) ::
          {:ok, Credentials.UserCertificate.t()} | {:error, :no_certificate}
  defp load_certificate(company_id) do
    case Credentials.get_certificate_for_company(company_id) do
      nil -> {:error, :no_certificate}
      cert -> {:ok, cert}
    end
  end
end
