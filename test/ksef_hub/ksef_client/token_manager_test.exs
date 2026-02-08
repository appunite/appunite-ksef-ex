defmodule KsefHub.KsefClient.TokenManagerTest do
  use KsefHub.DataCase, async: false

  import Mox

  import KsefHub.Factory

  alias KsefHub.KsefClient.TokenManager

  setup :verify_on_exit!

  setup do
    company = insert(:company)

    # Ensure any existing TokenManager for this company is stopped
    case Registry.lookup(KsefHub.TokenManagerRegistry, company.id) do
      [{pid, _}] -> GenServer.stop(pid)
      [] -> :ok
    end

    {:ok, pid} = TokenManager.start_link(company.id)
    Mox.allow(KsefHub.KsefClient.Mock, self(), pid)
    %{company: company, tm_pid: pid}
  end

  describe "ensure_access_token/1" do
    test "returns :reauth_required when no tokens stored", %{company: company} do
      assert {:error, :reauth_required} = TokenManager.ensure_access_token(company.id)
    end

    test "returns valid access token", %{company: company} do
      future = DateTime.add(DateTime.utc_now(), 600)
      refresh_future = DateTime.add(DateTime.utc_now(), 48 * 24 * 3600)

      :ok =
        TokenManager.store_tokens(company.id, "access-tok", "refresh-tok", future, refresh_future)

      assert {:ok, "access-tok"} = TokenManager.ensure_access_token(company.id)
    end

    test "refreshes expired access token using refresh token", %{company: company} do
      # Access token is about to expire (within buffer)
      expired = DateTime.add(DateTime.utc_now(), 60)
      refresh_future = DateTime.add(DateTime.utc_now(), 48 * 24 * 3600)

      :ok =
        TokenManager.store_tokens(
          company.id,
          "old-access",
          "refresh-tok",
          expired,
          refresh_future
        )

      new_valid_until = DateTime.add(DateTime.utc_now(), 900)

      KsefHub.KsefClient.Mock
      |> expect(:refresh_access_token, fn "refresh-tok" ->
        {:ok, %{access_token: "new-access", valid_until: new_valid_until}}
      end)

      assert {:ok, "new-access"} = TokenManager.ensure_access_token(company.id)
    end
  end

  describe "refresh_token_expires_at/1" do
    test "returns nil when no tokens", %{company: company} do
      assert TokenManager.refresh_token_expires_at(company.id) == nil
    end

    test "returns expiry datetime", %{company: company} do
      future = DateTime.add(DateTime.utc_now(), 600)
      refresh_future = DateTime.add(DateTime.utc_now(), 48 * 24 * 3600)

      :ok = TokenManager.store_tokens(company.id, "access", "refresh", future, refresh_future)

      result = TokenManager.refresh_token_expires_at(company.id)
      assert DateTime.compare(result, DateTime.utc_now()) == :gt
    end
  end
end
