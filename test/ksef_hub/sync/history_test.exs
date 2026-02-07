defmodule KsefHub.Sync.HistoryTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Sync.History

  describe "list_sync_jobs/1" do
    test "returns empty list when no sync jobs exist" do
      assert History.list_sync_jobs() == []
    end

    test "returns formatted sync jobs ordered by inserted_at desc" do
      now = DateTime.utc_now()
      earlier = DateTime.add(now, -600, :second)

      insert(:sync_job, inserted_at: earlier, state: "completed")
      insert(:sync_job, inserted_at: now, state: "completed")

      jobs = History.list_sync_jobs()
      assert length(jobs) == 2
      # Most recent first
      assert DateTime.compare(hd(jobs).inserted_at, List.last(jobs).inserted_at) == :gt
    end

    test "respects limit option" do
      for _ <- 1..5, do: insert(:sync_job, state: "completed")

      assert length(History.list_sync_jobs(limit: 3)) == 3
    end

    test "extracts income and expense counts from meta" do
      insert(:sync_job,
        state: "completed",
        meta: %{"income_count" => 5, "expense_count" => 3}
      )

      [job] = History.list_sync_jobs()
      assert job.income_count == 5
      assert job.expense_count == 3
    end

    test "extracts error from meta" do
      insert(:sync_job,
        state: "discarded",
        meta: %{"error" => "connection timeout"}
      )

      [job] = History.list_sync_jobs()
      assert job.error == "connection timeout"
    end

    test "calculates duration from attempted_at to completed_at" do
      now = DateTime.utc_now()

      insert(:sync_job,
        state: "completed",
        attempted_at: DateTime.add(now, -30, :second),
        completed_at: now
      )

      [job] = History.list_sync_jobs()
      assert job.duration == 30
    end

    test "only returns SyncWorker jobs" do
      insert(:sync_job, state: "completed")

      Repo.insert!(%Oban.Job{
        worker: "SomeOtherWorker",
        queue: "default",
        args: %{},
        state: "completed"
      })

      assert length(History.list_sync_jobs()) == 1
    end
  end

  describe "trigger_manual_sync/0" do
    test "inserts a new sync job" do
      assert {:ok, %Oban.Job{}} = History.trigger_manual_sync()
    end

    test "returns error when sync is already executing" do
      insert(:sync_job, state: "executing")

      assert {:error, :already_running} = History.trigger_manual_sync()
    end
  end
end
