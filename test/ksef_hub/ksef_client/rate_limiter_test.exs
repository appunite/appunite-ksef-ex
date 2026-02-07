defmodule KsefHub.KsefClient.RateLimiterTest do
  use ExUnit.Case, async: false

  alias KsefHub.KsefClient.RateLimiter

  setup do
    # Start a fresh rate limiter for each test
    case GenServer.whereis(RateLimiter) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end

    {:ok, _pid} = RateLimiter.start_link()
    :ok
  end

  describe "wait_for_slot/1" do
    test "allows requests within limits" do
      assert :ok = RateLimiter.wait_for_slot(:download)
    end

    test "tracks multiple requests without blocking" do
      assert :ok = RateLimiter.wait_for_slot(:download)
      assert :ok = RateLimiter.wait_for_slot(:download)
      assert :ok = RateLimiter.wait_for_slot(:metadata)
    end
  end

  describe "handle_rate_limit/1" do
    test "sleeps for the specified duration plus jitter" do
      start = System.monotonic_time(:millisecond)
      RateLimiter.handle_rate_limit(1)
      elapsed = System.monotonic_time(:millisecond) - start

      # Should sleep at least 1 second
      assert elapsed >= 1000
    end
  end
end
