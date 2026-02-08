defmodule KsefHub.Sync.InvoiceFetcherTest do
  use KsefHub.DataCase, async: false

  import Mox

  import KsefHub.Factory

  alias KsefHub.Sync.InvoiceFetcher

  setup :verify_on_exit!

  setup do
    company = insert(:company, nip: "1234567890")
    %{company: company}
  end

  describe "fetch_all/5" do
    test "returns zero count when no invoices found", %{company: company} do
      KsefHub.KsefClient.Mock
      |> expect(:query_invoice_metadata, fn _token, _filters, _opts ->
        {:ok, %{invoices: [], has_more: false, is_truncated: false}}
      end)

      from = DateTime.add(DateTime.utc_now(), -3600)

      assert {:ok, 0, nil} =
               InvoiceFetcher.fetch_all("token", "income", company.nip, company.id, from)
    end

    test "fetches and upserts invoices", %{company: company} do
      xml = File.read!("test/support/fixtures/sample_income.xml")
      storage_date = DateTime.to_iso8601(DateTime.utc_now())

      KsefHub.KsefClient.Mock
      |> expect(:query_invoice_metadata, fn _token, _filters, _opts ->
        {:ok,
         %{
           invoices: [
             %{
               "ksefReferenceNumber" => "FETCH-001",
               "acquisitionTimestamp" => storage_date,
               "permanentStorageDate" => storage_date
             }
           ],
           has_more: false,
           is_truncated: false
         }}
      end)

      KsefHub.KsefClient.Mock
      |> expect(:download_invoice, fn _token, "FETCH-001" ->
        {:ok, xml}
      end)

      from = DateTime.add(DateTime.utc_now(), -3600)

      assert {:ok, 1, _max_ts} =
               InvoiceFetcher.fetch_all("token", "income", company.nip, company.id, from)

      invoice = KsefHub.Invoices.get_invoice_by_ksef_number(company.id, "FETCH-001")
      assert invoice != nil
      assert invoice.seller_nip == "1234567890"
    end

    test "handles pagination (has_more)", %{company: company} do
      xml = File.read!("test/support/fixtures/sample_income.xml")
      storage_date = DateTime.to_iso8601(DateTime.utc_now())

      # Page 1
      KsefHub.KsefClient.Mock
      |> expect(:query_invoice_metadata, fn _t, _f, opts ->
        case Keyword.get(opts, :page_offset) do
          0 ->
            {:ok,
             %{
               invoices: [
                 %{
                   "ksefReferenceNumber" => "PAGE-001",
                   "acquisitionTimestamp" => storage_date,
                   "permanentStorageDate" => storage_date
                 }
               ],
               has_more: true,
               is_truncated: false
             }}
        end
      end)

      # Page 2
      KsefHub.KsefClient.Mock
      |> expect(:query_invoice_metadata, fn _t, _f, opts ->
        1 = Keyword.get(opts, :page_offset)
        {:ok, %{invoices: [], has_more: false, is_truncated: false}}
      end)

      KsefHub.KsefClient.Mock
      |> expect(:download_invoice, fn _t, "PAGE-001" -> {:ok, xml} end)

      from = DateTime.add(DateTime.utc_now(), -3600)

      assert {:ok, 1, _} =
               InvoiceFetcher.fetch_all("token", "income", company.nip, company.id, from)
    end

    test "handles rate limiting with retry", %{company: company} do
      KsefHub.KsefClient.Mock
      |> expect(:query_invoice_metadata, fn _t, _f, _o ->
        {:error, {:rate_limited, 1}}
      end)

      # After retry, returns empty
      KsefHub.KsefClient.Mock
      |> expect(:query_invoice_metadata, fn _t, _f, _o ->
        {:ok, %{invoices: [], has_more: false, is_truncated: false}}
      end)

      from = DateTime.add(DateTime.utc_now(), -3600)

      assert {:ok, 0, nil} =
               InvoiceFetcher.fetch_all("token", "income", company.nip, company.id, from)
    end
  end
end
