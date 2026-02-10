defmodule KsefHub.KsefClient.AuthWorker do
  @moduledoc """
  Oban worker that performs XADES authentication after a certificate upload.

  Decrypts the stored certificate, runs the full XADES auth flow
  (challenge → sign → authenticate → poll → redeem), and stores the
  resulting tokens via TokenManager so the next sync cycle succeeds.
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 60]

  require Logger

  alias KsefHub.Credentials
  alias KsefHub.Credentials.Encryption
  alias KsefHub.KsefClient.{Auth, TokenManager}

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()} | {:cancel, term()}
  def perform(%Oban.Job{args: %{"company_id" => company_id}}) do
    with {:ok, credential} <- load_credential(company_id),
         {:ok, user_cert} <- load_certificate(company_id),
         {:ok, cert_data} <- Encryption.decrypt(user_cert.certificate_data_encrypted),
         {:ok, password} <- Encryption.decrypt(user_cert.certificate_password_encrypted),
         {:ok, tokens} <- Auth.authenticate(credential.nip, cert_data, password) do
      TokenManager.store_tokens(
        company_id,
        tokens.access_token,
        tokens.refresh_token,
        tokens.access_valid_until,
        tokens.refresh_valid_until
      )

      Logger.info("AuthWorker: initial authentication successful for company #{company_id}")
      :ok
    else
      {:error, :no_credential} ->
        Logger.warning("AuthWorker: no active credential for company #{company_id}, cancelling")
        {:cancel, :no_credential}

      {:error, :no_certificate} ->
        Logger.warning("AuthWorker: no owner certificate for company #{company_id}, cancelling")

        {:cancel, :no_certificate}

      {:error, reason} ->
        Logger.error(
          "AuthWorker: authentication failed for company #{company_id}: #{inspect(reason)}"
        )

        {:error, reason}
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
