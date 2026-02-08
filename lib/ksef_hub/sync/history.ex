defmodule KsefHub.Sync.History do
  @moduledoc """
  Queries Oban job history for sync runs and supports manual sync triggers.
  """

  import Ecto.Query

  alias KsefHub.Repo
  alias KsefHub.Sync.SyncWorker

  @worker "KsefHub.Sync.SyncWorker"

  @doc """
  Lists recent sync jobs for a company, most recent first.

  ## Options

    * `:limit` — max rows to return (default 50)
  """
  @spec list_sync_jobs(Ecto.UUID.t(), keyword()) :: [map()]
  def list_sync_jobs(company_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Oban.Job
    |> where([j], j.worker == @worker)
    |> where([j], fragment("?->>'company_id' = ?", j.args, ^company_id))
    |> order_by([j], desc: j.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&format_job/1)
  end

  @doc """
  Inserts a manual sync job for a company if no sync is currently executing.

  Returns `{:ok, job}` or `{:error, :already_running}`.
  """
  @spec trigger_manual_sync(Ecto.UUID.t()) ::
          {:ok, Oban.Job.t()} | {:error, :already_running | Ecto.Changeset.t()}
  def trigger_manual_sync(company_id) do
    executing =
      Oban.Job
      |> where([j], j.worker == @worker and j.state == "executing")
      |> where([j], fragment("?->>'company_id' = ?", j.args, ^company_id))
      |> Repo.exists?()

    if executing do
      {:error, :already_running}
    else
      %{company_id: company_id, manual: true}
      |> SyncWorker.new()
      |> Oban.insert()
    end
  end

  @spec format_job(Oban.Job.t()) :: map()
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

  @spec duration(DateTime.t() | nil, DateTime.t() | nil) :: non_neg_integer() | nil
  defp duration(nil, _), do: nil
  defp duration(_, nil), do: nil

  defp duration(attempted_at, completed_at) do
    DateTime.diff(completed_at, attempted_at, :second)
  end

  @spec format_errors(list() | term()) :: String.t() | nil
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
