defmodule KsefHub.Sync.SyncWorker do
  @moduledoc """
  Oban worker that syncs invoices from KSeF every 15 minutes.
  Full implementation in Phase 4.
  """

  use Oban.Worker, queue: :sync, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id}) do
    Logger.warning("KSeF sync job ##{job_id} scheduled but not yet implemented")
    :ok
  end
end
