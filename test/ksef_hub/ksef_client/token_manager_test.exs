defmodule KsefHub.KsefClient.TokenManagerTest do
  use KsefHub.DataCase, async: false

  import Mox

  alias KsefHub.KsefClient.TokenManager

  setup :verify_on_exit!

  setup do
    # Stop any existing TokenManager
    case GenServer.whereis(TokenManager) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end

    {:ok, pid} = TokenManager.start_link()
    # Allow the GenServer process to use Mox expectations set in the test process
    Mox.allow(KsefHub.KsefClient.Mock, self(), pid)
    :ok
  end

  describe "ensure_access_token/0" do
    test "returns :reauth_required when no tokens stored" do
      assert {:error, :reauth_required} = TokenManager.ensure_access_token()
    end

    test "returns valid access token" do
      future = DateTime.add(DateTime.utc_now(), 600)
      refresh_future = DateTime.add(DateTime.utc_now(), 48 * 24 * 3600)

      :ok = TokenManager.store_tokens("access-tok", "refresh-tok", future, refresh_future)

      assert {:ok, "access-tok"} = TokenManager.ensure_access_token()
    end

    test "refreshes expired access token using refresh token" do
      # Access token is about to expire (within buffer)
      expired = DateTime.add(DateTime.utc_now(), 60)
      refresh_future = DateTime.add(DateTime.utc_now(), 48 * 24 * 3600)

      :ok = TokenManager.store_tokens("old-access", "refresh-tok", expired, refresh_future)

      new_valid_until = DateTime.add(DateTime.utc_now(), 900)

      KsefHub.KsefClient.Mock
      |> expect(:refresh_access_token, fn "refresh-tok" ->
        {:ok, %{access_token: "new-access", valid_until: new_valid_until}}
      end)

      assert {:ok, "new-access"} = TokenManager.ensure_access_token()
    end
  end

  describe "refresh_token_expires_at/0" do
    test "returns nil when no tokens" do
      assert TokenManager.refresh_token_expires_at() == nil
    end

    test "returns expiry datetime" do
      future = DateTime.add(DateTime.utc_now(), 600)
      refresh_future = DateTime.add(DateTime.utc_now(), 48 * 24 * 3600)

      :ok = TokenManager.store_tokens("access", "refresh", future, refresh_future)

      result = TokenManager.refresh_token_expires_at()
      assert DateTime.compare(result, DateTime.utc_now()) == :gt
    end
  end
end
