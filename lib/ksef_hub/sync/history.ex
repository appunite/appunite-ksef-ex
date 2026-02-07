defmodule KsefHub.Sync.History do
  @moduledoc """
  Queries Oban job history for sync runs and supports manual sync triggers.
  """

  import Ecto.Query

  alias KsefHub.Repo
  alias KsefHub.Sync.SyncWorker

  @worker "KsefHub.Sync.SyncWorker"

  @doc """
  Lists recent sync jobs, most recent first.

  ## Options

    * `:limit` — max rows to return (default 50)
  """
  def list_sync_jobs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Oban.Job
    |> where([j], j.worker == @worker)
    |> order_by([j], desc: j.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&format_job/1)
  end

  @doc """
  Inserts a manual sync job if no sync is currently executing.

  Returns `{:ok, job}` or `{:error, :already_running}`.
  """
  def trigger_manual_sync do
    executing =
      Oban.Job
      |> where([j], j.worker == @worker and j.state == "executing")
      |> Repo.exists?()

    if executing do
      {:error, :already_running}
    else
      %{manual: true}
      |> SyncWorker.new()
      |> Oban.insert()
    end
  end

  defp format_job(%Oban.Job{} = job) do
    %{
      id: job.id,
      state: job.state,
      inserted_at: job.inserted_at,
      attempted_at: job.attempted_at,
      completed_at: job.completed_at,
      duration: duration(job.attempted_at, job.completed_at),
      income_count: get_in(job.meta, ["income_count"]),
      expense_count: get_in(job.meta, ["expense_count"]),
      error: get_in(job.meta, ["error"]) || format_errors(job.errors)
    }
  end

  defp duration(nil, _), do: nil
  defp duration(_, nil), do: nil

  defp duration(attempted_at, completed_at) do
    DateTime.diff(completed_at, attempted_at, :second)
  end

  defp format_errors([]), do: nil

  defp format_errors(errors) when is_list(errors) do
    errors
    |> List.last()
    |> case do
      %{"error" => msg} -> msg
      _ -> nil
    end
  end

  defp format_errors(_), do: nil
end
