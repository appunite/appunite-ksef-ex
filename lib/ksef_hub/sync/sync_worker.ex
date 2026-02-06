defmodule KsefHub.Sync.SyncWorker do
  @moduledoc """
  Oban worker that syncs invoices from KSeF every 15 minutes.
  Full implementation in Phase 4.
  """

  use Oban.Worker, queue: :sync, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # TODO: Implement in Phase 4
    :ok
  end
end
