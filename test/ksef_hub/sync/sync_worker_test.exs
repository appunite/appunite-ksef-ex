defmodule KsefHub.Sync.SyncWorkerTest do
  use KsefHub.DataCase, async: false

  import Mox

  alias KsefHub.Credentials
  alias KsefHub.KsefClient.TokenManager
  alias KsefHub.Sync.SyncWorker

  setup :verify_on_exit!

  setup do
    # Stop any existing TokenManager
    case GenServer.whereis(TokenManager) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end

    {:ok, pid} = TokenManager.start_link()
    Mox.allow(KsefHub.KsefClient.Mock, self(), pid)
    :ok
  end

  describe "perform/1" do
    test "skips sync when no active credential" do
      assert :ok = SyncWorker.perform(%Oban.Job{})
    end

    test "syncs invoices when credential and tokens are available" do
      # Create credential
      {:ok, cred} = Credentials.create_credential(%{nip: "1234567890"})

      # Store valid tokens
      future = DateTime.add(DateTime.utc_now(), 600)
      refresh_future = DateTime.add(DateTime.utc_now(), 48 * 24 * 3600)
      :ok = TokenManager.store_tokens("access-tok", "refresh-tok", future, refresh_future)

      # Mock empty query results (no invoices to sync)
      KsefHub.KsefClient.Mock
      |> expect(:query_invoice_metadata, 2, fn "access-tok", _filters, _opts ->
        {:ok, %{invoices: [], has_more: false, is_truncated: false}}
      end)

      assert :ok = SyncWorker.perform(%Oban.Job{})

      # Verify last_sync_at was updated
      updated = Repo.get!(Credentials.Credential, cred.id)
      assert updated.last_sync_at != nil
    end

    test "downloads and upserts invoices from KSeF" do
      xml = File.read!("test/support/fixtures/sample_income.xml")

      {:ok, _cred} = Credentials.create_credential(%{nip: "1234567890"})

      future = DateTime.add(DateTime.utc_now(), 600)
      refresh_future = DateTime.add(DateTime.utc_now(), 48 * 24 * 3600)
      :ok = TokenManager.store_tokens("access-tok", "refresh-tok", future, refresh_future)

      storage_date = DateTime.to_iso8601(DateTime.utc_now())

      # Income query returns one invoice header
      KsefHub.KsefClient.Mock
      |> expect(:query_invoice_metadata, fn "access-tok", %{type: "income"}, _opts ->
        {:ok,
         %{
           invoices: [
             %{
               "ksefReferenceNumber" => "KSEF-INCOME-001",
               "acquisitionTimestamp" => storage_date,
               "permanentStorageDate" => storage_date
             }
           ],
           has_more: false,
           is_truncated: false
         }}
      end)

      # Expense query returns empty
      KsefHub.KsefClient.Mock
      |> expect(:query_invoice_metadata, fn "access-tok", %{type: "expense"}, _opts ->
        {:ok, %{invoices: [], has_more: false, is_truncated: false}}
      end)

      # Download the income invoice
      KsefHub.KsefClient.Mock
      |> expect(:download_invoice, fn "access-tok", "KSEF-INCOME-001" ->
        {:ok, xml}
      end)

      assert :ok = SyncWorker.perform(%Oban.Job{})

      # Verify invoice was created
      invoice = KsefHub.Invoices.get_invoice_by_ksef_number("KSEF-INCOME-001")
      assert invoice != nil
      assert invoice.type == "income"
      assert invoice.seller_nip == "1234567890"
      assert invoice.invoice_number == "FV/2025/001"
    end
  end
end
