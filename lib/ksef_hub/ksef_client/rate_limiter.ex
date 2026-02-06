defmodule KsefHub.KsefClient.RateLimiter do
  @moduledoc """
  Rate limiter for KSeF API requests.
  Enforces per-second, per-minute, and per-hour limits.

  KSeF rate limits:
  - Metadata queries: 80 req/s, 160/min, 200/hour
  - Invoice downloads: 80 req/s, 160/min, 640/hour
  """

  use GenServer

  @windows %{
    metadata: %{per_second: 80, per_minute: 160, per_hour: 200},
    download: %{per_second: 80, per_minute: 160, per_hour: 640}
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Waits until the request can be made within rate limits.
  Returns `:ok` when ready to proceed.
  """
  def wait_for_slot(operation_type \\ :download) do
    GenServer.call(__MODULE__, {:wait, operation_type}, 60_000)
  end

  @doc """
  Records a completed request.
  """
  def record_request(operation_type \\ :download) do
    GenServer.cast(__MODULE__, {:record, operation_type})
  end

  @doc """
  Handles a 429 response by sleeping for the retry-after duration.
  """
  def handle_rate_limit(retry_after_seconds) do
    jitter = :rand.uniform(1000)
    Process.sleep(retry_after_seconds * 1000 + jitter)
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    {:ok, %{metadata: [], download: []}}
  end

  @impl true
  def handle_call({:wait, operation_type}, _from, state) do
    timestamps = Map.get(state, operation_type, [])
    now = System.monotonic_time(:millisecond)
    limits = Map.get(@windows, operation_type, @windows.download)

    wait_ms = calculate_wait(timestamps, now, limits)

    if wait_ms > 0 do
      Process.sleep(wait_ms)
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:record, operation_type}, state) do
    now = System.monotonic_time(:millisecond)
    timestamps = Map.get(state, operation_type, [])
    # Keep only last hour of timestamps
    cutoff = now - 3_600_000
    cleaned = Enum.filter(timestamps, &(&1 > cutoff))
    {:noreply, Map.put(state, operation_type, [now | cleaned])}
  end

  # --- Private ---

  defp calculate_wait(timestamps, now, limits) do
    waits = [
      check_window(timestamps, now, 1_000, limits.per_second),
      check_window(timestamps, now, 60_000, limits.per_minute),
      check_window(timestamps, now, 3_600_000, limits.per_hour)
    ]

    Enum.max(waits)
  end

  defp check_window(timestamps, now, window_ms, limit) do
    cutoff = now - window_ms
    count = Enum.count(timestamps, &(&1 > cutoff))

    if count >= limit do
      oldest_in_window =
        timestamps
        |> Enum.filter(&(&1 > cutoff))
        |> Enum.min(fn -> now end)

      oldest_in_window + window_ms - now + 1
    else
      0
    end
  end
end
