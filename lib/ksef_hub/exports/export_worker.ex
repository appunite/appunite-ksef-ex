defmodule KsefHub.Exports.ExportWorker do
  @moduledoc """
  Oban worker that generates export ZIP files asynchronously.

  Enqueued by `Exports.create_export/3`. Loads the batch, generates PDFs + CSV,
  builds ZIP, stores the file, and marks the batch as completed or failed.
  """

  use Oban.Worker, queue: :exports, max_attempts: 2

  require Logger

  alias KsefHub.Exports
  alias KsefHub.Exports.ExportBatch
  alias KsefHub.Repo

  @doc "Generates the export ZIP for the given batch. Called by Oban."
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:cancel, String.t()} | {:error, term()}
  def perform(%Oban.Job{args: %{"export_batch_id" => batch_id}}) do
    case Repo.get(ExportBatch, batch_id) do
      nil ->
        {:cancel, "export batch not found"}

      %ExportBatch{status: status} when status in [:completed, :failed] ->
        {:cancel, "export batch already #{status}"}

      %ExportBatch{} = batch ->
        case Exports.generate_export(batch) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.error(
              "Export generation failed for batch #{batch_id}: #{inspect(reason, limit: 200)}"
            )

            {:error, reason}
        end
    end
  end

  def perform(%Oban.Job{args: args}) do
    Logger.error("ExportWorker received malformed args: #{inspect(args, limit: 200)}")
    {:cancel, "malformed job args: missing export_batch_id"}
  end
end
