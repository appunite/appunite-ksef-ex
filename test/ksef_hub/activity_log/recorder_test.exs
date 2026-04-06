defmodule RecorderTest do
  use KsefHub.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias KsefHub.ActivityLog.{Event, Recorder}
  alias KsefHub.AuditLog
  alias KsefHub.Repo

  import KsefHub.Factory

  @pubsub KsefHub.PubSub

  setup do
    recorder = start_test_recorder()
    %{recorder: recorder}
  end

  describe "handle_info/2 with activity events" do
    test "persists a valid event to the database" do
      company = insert(:company)
      user = insert(:user)

      event = %Event{
        action: "invoice.created",
        resource_type: "invoice",
        resource_id: Ecto.UUID.generate(),
        company_id: company.id,
        user_id: user.id,
        actor_type: :user,
        actor_label: user.name,
        metadata: %{source: "ksef"}
      }

      send_and_wait(event)

      assert [log] = Repo.all(AuditLog)
      assert log.action == "invoice.created"
      assert log.resource_type == "invoice"
      assert log.resource_id == event.resource_id
      assert log.company_id == company.id
      assert log.user_id == user.id
      assert log.actor_type == :user
      assert log.actor_label == user.name
      assert log.metadata == %{"source" => "ksef"}
    end

    test "persists system events without user_id" do
      company = insert(:company)

      event = %Event{
        action: "sync.completed",
        resource_type: "sync",
        company_id: company.id,
        actor_type: :system,
        actor_label: "KSeF Sync",
        metadata: %{income: 5, expense: 3}
      }

      send_and_wait(event)

      assert [log] = Repo.all(AuditLog)
      assert log.action == "sync.completed"
      assert log.actor_type == :system
      assert log.actor_label == "KSeF Sync"
      assert log.user_id == nil
    end

    test "broadcasts to resource-specific topic after insert" do
      company = insert(:company)
      invoice_id = Ecto.UUID.generate()

      Phoenix.PubSub.subscribe(@pubsub, "activity:invoice:#{invoice_id}")

      event = %Event{
        action: "invoice.status_changed",
        resource_type: "invoice",
        resource_id: invoice_id,
        company_id: company.id,
        actor_type: :user,
        metadata: %{old_status: "pending", new_status: "approved"}
      }

      send_and_wait(event)

      assert_received {:new_activity, %AuditLog{action: "invoice.status_changed"}}
    end

    test "does not crash on events without resource info", %{recorder: recorder} do
      event = %Event{
        action: "user.logged_in",
        actor_type: :user,
        actor_label: "Jan Kowalski"
      }

      send_and_wait(event)

      assert [log] = Repo.all(AuditLog)
      assert log.action == "user.logged_in"
      assert Process.alive?(recorder)
    end

    test "does not crash the recorder on invalid messages", %{recorder: recorder} do
      send(recorder, {:activity_event, :bad_data})
      # Use :sys.get_state to synchronize — forces the GenServer to process all prior messages
      :sys.get_state(recorder)

      assert Process.alive?(recorder)
    end
  end

  # Sends an event directly to the Recorder (bypassing the Events module's emitter)
  # and waits for it to be processed using :sys.get_state for synchronization.
  defp send_and_wait(event) do
    recorder = Process.whereis(Recorder)
    send(recorder, {:activity_event, event})
    :sys.get_state(recorder)
  end

  defp start_test_recorder do
    case GenServer.whereis(Recorder) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end

    {:ok, pid} =
      GenServer.start_link(
        Recorder,
        [enabled: true],
        name: Recorder
      )

    Sandbox.allow(Repo, self(), pid)
    pid
  end
end
