defmodule KsefHub.Sync.SyncDispatcher do
  @moduledoc """
  Oban cron worker that dispatches per-company sync jobs.
  Runs every 15 minutes, queries all companies with active credentials,
  and enqueues one SyncWorker job per company.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  alias KsefHub.Credentials
  alias KsefHub.Sync.SyncWorker

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    credentials = Credentials.list_active_credentials()

    Logger.info("SyncDispatcher: dispatching sync for #{length(credentials)} companies")

    Enum.each(credentials, fn credential ->
      %{company_id: credential.company_id}
      |> SyncWorker.new(unique: [period: 300, fields: [:args, :queue, :worker]])
      |> Oban.insert()
    end)

    :ok
  end
end
