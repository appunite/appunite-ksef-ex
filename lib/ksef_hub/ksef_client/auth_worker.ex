defmodule KsefHub.KsefClient.AuthWorker do
  @moduledoc """
  Oban worker that performs XADES authentication after a certificate upload.

  Delegates to `Authenticator.authenticate_and_store/1` for the actual auth flow,
  and maps the results to Oban return values (`:ok`, `{:error, _}`, `{:cancel, _}`).
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 60]

  require Logger

  alias KsefHub.KsefClient.Authenticator

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()} | {:cancel, term()}
  def perform(%Oban.Job{args: %{"company_id" => company_id}}) do
    case Authenticator.authenticate_and_store(company_id) do
      {:ok, _access_token} ->
        Logger.info("AuthWorker: initial authentication successful for company #{company_id}")
        :ok

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
end
