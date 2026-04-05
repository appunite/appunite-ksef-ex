defmodule KsefHub.ActivityLog.TestEmitter do
  @moduledoc """
  Test emitter for the activity log. Instead of broadcasting via PubSub,
  sends events to the test process for synchronous assertions.

  Uses the `$callers` process metadata (set by Ecto sandbox) to find the
  owning test process, making it safe for `async: true` tests.

  ## Usage in tests

      setup do
        KsefHub.ActivityLog.TestEmitter.attach(self())
        :ok
      end

      test "approve_invoice broadcasts status_changed event" do
        {:ok, _invoice} = Invoices.approve_invoice(invoice, opts)

        assert_received {:activity_event, %Event{action: "invoice.status_changed"}}
      end
  """

  @doc """
  Registers the calling process to receive events.
  Stores the PID in the process dictionary of the calling process.
  """
  @spec attach(pid()) :: :ok
  def attach(pid) do
    Process.put(:activity_log_test_pid, pid)
    :ok
  end

  @doc """
  Emits an event by sending it to the registered test process.

  Walks the `$callers` chain to find the process that called `attach/1`,
  which is the test process owning this sandbox connection.
  """
  @spec emit(KsefHub.ActivityLog.Event.t()) :: :ok
  def emit(event) do
    case find_test_pid() do
      nil -> :ok
      pid -> send(pid, {:activity_event, event})
    end

    :ok
  end

  @spec find_test_pid() :: pid() | nil
  defp find_test_pid do
    Process.get(:activity_log_test_pid) || find_test_pid_in_callers()
  end

  @spec find_test_pid_in_callers() :: pid() | nil
  defp find_test_pid_in_callers do
    :"$callers"
    |> Process.get([])
    |> Enum.find_value(&read_test_pid_from_process/1)
  end

  @spec read_test_pid_from_process(pid()) :: pid() | nil
  defp read_test_pid_from_process(pid) do
    with true <- Process.alive?(pid),
         {:dictionary, dict} <- Process.info(pid, :dictionary) do
      Keyword.get(dict, :activity_log_test_pid)
    else
      _ -> nil
    end
  end
end
