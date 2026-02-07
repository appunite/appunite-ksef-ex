defmodule KsefHub.KsefClient.RateLimiter do
  @moduledoc """
  Rate limiter for KSeF API requests.
  Enforces per-second, per-minute, and per-hour limits.

  KSeF rate limits:
  - Metadata queries: 80 req/s, 160/min, 200/hour
  - Invoice downloads: 80 req/s, 160/min, 640/hour

  Usage:

      :ok = RateLimiter.wait_for_slot(:download)
      result = do_request()

  `wait_for_slot/1` atomically records the request and sleeps in the
  caller's process (not inside the GenServer) so concurrent callers
  are not serialised behind a single sleeping process.
  """

  use GenServer

  @windows %{
    metadata: %{per_second: 80, per_minute: 160, per_hour: 200},
    download: %{per_second: 80, per_minute: 160, per_hour: 640}
  }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Waits until the request can be made within rate limits, then records it.
  The sleep happens in the calling process so the GenServer stays responsive.
  Returns `:ok` when ready to proceed.
  """
  @spec wait_for_slot(:metadata | :download) :: :ok
  def wait_for_slot(operation_type \\ :download) do
    wait_ms = GenServer.call(__MODULE__, {:acquire, operation_type}, :infinity)

    if wait_ms > 0 do
      Process.sleep(wait_ms)
    end

    :ok
  end

  @doc """
  Handles a 429 response by sleeping for the retry-after duration with jitter.
  """
  @spec handle_rate_limit(non_neg_integer()) :: :ok
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
  def handle_call({:acquire, operation_type}, _from, state) do
    now = System.monotonic_time(:millisecond)
    timestamps = Map.get(state, operation_type, [])
    limits = Map.get(@windows, operation_type, @windows.download)

    wait_ms = calculate_wait(timestamps, now, limits)

    # Record the request at the time it will actually execute
    effective_time = now + max(wait_ms, 0)
    cutoff = effective_time - 3_600_000
    cleaned = Enum.filter(timestamps, &(&1 > cutoff))
    new_state = Map.put(state, operation_type, [effective_time | cleaned])

    {:reply, wait_ms, new_state}
  end

  # --- Private ---

  @spec calculate_wait([integer()], integer(), map()) :: integer()
  defp calculate_wait(timestamps, now, limits) do
    [
      check_window(timestamps, now, 1_000, limits.per_second),
      check_window(timestamps, now, 60_000, limits.per_minute),
      check_window(timestamps, now, 3_600_000, limits.per_hour)
    ]
    |> Enum.max()
  end

  @spec check_window([integer()], integer(), integer(), integer()) :: integer()
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
