defmodule KsefHub.Files.OrphanCleanupWorker do
  @moduledoc """
  Oban cron worker that deletes orphaned file records.

  A file is considered orphaned if it is not referenced by any invoice
  (xml_file_id or pdf_file_id) or inbound_email (pdf_file_id) and is
  older than 24 hours. The age threshold prevents deleting files that
  are in-flight during a transaction.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

  require Logger

  alias KsefHub.Repo

  @batch_size 100
  @retention_hours 24

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{}) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-@retention_hours * 3600)
      |> DateTime.truncate(:microsecond)

    orphan_query()
    |> where([f], f.inserted_at < ^cutoff)
    |> select([f], f.id)
    |> Repo.all()
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(fn ids ->
      {count, _} = Repo.delete_all(from(f in KsefHub.Files.File, where: f.id in ^ids))
      if count > 0, do: Logger.info("OrphanCleanupWorker: deleted #{count} orphaned files")
    end)

    :ok
  end

  # NOTE: If a new table adds a FK to files, add a LEFT JOIN here to avoid
  # deleting files that are still referenced.
  @spec orphan_query() :: Ecto.Query.t()
  defp orphan_query do
    from(f in KsefHub.Files.File,
      left_join: ix in "invoices",
      on: ix.xml_file_id == f.id,
      left_join: ip in "invoices",
      on: ip.pdf_file_id == f.id,
      left_join: ie in "inbound_emails",
      on: ie.pdf_file_id == f.id,
      where: is_nil(ix.id) and is_nil(ip.id) and is_nil(ie.id)
    )
  end
end
