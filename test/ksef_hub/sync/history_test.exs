defmodule KsefHub.Sync.HistoryTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Sync.History

  setup do
    company = insert(:company)
    %{company: company}
  end

  describe "list_sync_jobs/1" do
    test "returns empty list when no sync jobs exist", %{company: company} do
      assert History.list_sync_jobs(company.id) == []
    end

    test "returns formatted sync jobs ordered by inserted_at desc", %{company: company} do
      now = DateTime.utc_now()
      earlier = DateTime.add(now, -600, :second)

      insert(:sync_job,
        inserted_at: earlier,
        state: "completed",
        args: %{"company_id" => company.id}
      )

      insert(:sync_job,
        inserted_at: now,
        state: "completed",
        args: %{"company_id" => company.id}
      )

      jobs = History.list_sync_jobs(company.id)
      assert length(jobs) == 2
      # Most recent first
      assert DateTime.compare(hd(jobs).inserted_at, List.last(jobs).inserted_at) == :gt
    end

    test "respects limit option", %{company: company} do
      for _ <- 1..5,
          do: insert(:sync_job, state: "completed", args: %{"company_id" => company.id})

      assert length(History.list_sync_jobs(company.id, limit: 3)) == 3
    end

    test "extracts income and expense counts from meta", %{company: company} do
      insert(:sync_job,
        state: "completed",
        meta: %{"income_count" => 5, "expense_count" => 3},
        args: %{"company_id" => company.id}
      )

      [job] = History.list_sync_jobs(company.id)
      assert job.income_count == 5
      assert job.expense_count == 3
    end

    test "extracts error from meta", %{company: company} do
      insert(:sync_job,
        state: "discarded",
        meta: %{"error" => "connection timeout"},
        args: %{"company_id" => company.id}
      )

      [job] = History.list_sync_jobs(company.id)
      assert job.error == "connection timeout"
    end

    test "hides stale errors from job.errors when job completed on retry", %{company: company} do
      insert(:sync_job,
        state: "completed",
        meta: %{"income_count" => 2, "expense_count" => 1},
        errors: [%{"at" => "2026-02-11T10:00:00Z", "attempt" => 1, "error" => "timeout"}],
        args: %{"company_id" => company.id}
      )

      [job] = History.list_sync_jobs(company.id)
      assert job.state == "completed"
      assert job.error == nil
    end

    test "shows error from job.errors for non-completed jobs", %{company: company} do
      insert(:sync_job,
        state: "retryable",
        meta: %{},
        errors: [%{"at" => "2026-02-11T10:00:00Z", "attempt" => 1, "error" => "timeout"}],
        args: %{"company_id" => company.id}
      )

      [job] = History.list_sync_jobs(company.id)
      assert job.error == "timeout"
    end

    test "calculates duration from attempted_at to completed_at", %{company: company} do
      now = DateTime.utc_now()

      insert(:sync_job,
        state: "completed",
        attempted_at: DateTime.add(now, -30, :second),
        completed_at: now,
        args: %{"company_id" => company.id}
      )

      [job] = History.list_sync_jobs(company.id)
      assert job.duration == 30
    end

    test "only returns SyncWorker jobs", %{company: company} do
      insert(:sync_job, state: "completed", args: %{"company_id" => company.id})

      Repo.insert!(%Oban.Job{
        worker: "SomeOtherWorker",
        queue: "default",
        args: %{"company_id" => company.id},
        state: "completed"
      })

      assert length(History.list_sync_jobs(company.id)) == 1
    end

    test "only returns jobs for the specified company", %{company: company} do
      other_company = insert(:company)

      insert(:sync_job, state: "completed", args: %{"company_id" => company.id})
      insert(:sync_job, state: "completed", args: %{"company_id" => other_company.id})

      assert length(History.list_sync_jobs(company.id)) == 1
    end
  end

  describe "trigger_manual_sync/1" do
    test "inserts a new sync job", %{company: company} do
      assert {:ok, %Oban.Job{}} = History.trigger_manual_sync(company.id)
    end

    test "returns error when sync is already executing", %{company: company} do
      insert(:sync_job, state: "executing", args: %{"company_id" => company.id})

      assert {:error, :already_running} = History.trigger_manual_sync(company.id)
    end

    test "returns error when sync job is queued (available)", %{company: company} do
      insert(:sync_job, state: "available", args: %{"company_id" => company.id})

      assert {:error, :already_running} = History.trigger_manual_sync(company.id)
    end

    test "returns error when sync job is scheduled", %{company: company} do
      insert(:sync_job, state: "scheduled", args: %{"company_id" => company.id})

      assert {:error, :already_running} = History.trigger_manual_sync(company.id)
    end
  end
end
