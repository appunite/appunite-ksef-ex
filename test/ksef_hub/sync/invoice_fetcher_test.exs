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

      assert {:ok, 0, nil, 0} =
               InvoiceFetcher.fetch_all("token", :income, company.nip, company.id, from)
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
               "ksefNumber" => "FETCH-001",
               "acquisitionDate" => storage_date,
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

      assert {:ok, 1, _max_ts, 0} =
               InvoiceFetcher.fetch_all("token", :income, company.nip, company.id, from)

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
                   "ksefNumber" => "PAGE-001",
                   "acquisitionDate" => storage_date,
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

      assert {:ok, 1, _, 0} =
               InvoiceFetcher.fetch_all("token", :income, company.nip, company.id, from)
    end

    test "does not count re-synced (updated) invoices", %{company: company} do
      xml = File.read!("test/support/fixtures/sample_income.xml")
      storage_date = DateTime.to_iso8601(DateTime.utc_now())

      # Pre-insert the invoice with a backdated timestamp so the upsert detects :updated
      insert(:invoice,
        ksef_number: "RESYNC-001",
        company: company,
        seller_nip: "1234567890",
        type: :income,
        inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
      )

      KsefHub.KsefClient.Mock
      |> expect(:query_invoice_metadata, fn _token, _filters, _opts ->
        {:ok,
         %{
           invoices: [
             %{
               "ksefNumber" => "RESYNC-001",
               "acquisitionDate" => storage_date,
               "permanentStorageDate" => storage_date
             }
           ],
           has_more: false,
           is_truncated: false
         }}
      end)

      KsefHub.KsefClient.Mock
      |> expect(:download_invoice, fn _token, "RESYNC-001" ->
        {:ok, xml}
      end)

      from = DateTime.add(DateTime.utc_now(), -3600)

      assert {:ok, 0, _max_ts, 0} =
               InvoiceFetcher.fetch_all("token", :income, company.nip, company.id, from)
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

      assert {:ok, 0, nil, 0} =
               InvoiceFetcher.fetch_all("token", :income, company.nip, company.id, from)
    end

    test "links correction invoice to existing original during sync", %{company: company} do
      correction_xml = File.read!("test/support/fixtures/sample_correction.xml")
      storage_date = DateTime.to_iso8601(DateTime.utc_now())

      # Pre-insert the original invoice that the correction references
      original =
        insert(:invoice,
          company: company,
          ksef_number: "7831812112-20260407-5B69FA00002B-9D",
          type: :income
        )

      KsefHub.KsefClient.Mock
      |> expect(:query_invoice_metadata, fn _token, _filters, _opts ->
        {:ok,
         %{
           invoices: [
             %{
               "ksefNumber" => "CORR-001",
               "acquisitionDate" => storage_date,
               "permanentStorageDate" => storage_date
             }
           ],
           has_more: false,
           is_truncated: false
         }}
      end)

      KsefHub.KsefClient.Mock
      |> expect(:download_invoice, fn _token, "CORR-001" ->
        {:ok, correction_xml}
      end)

      from = DateTime.add(DateTime.utc_now(), -3600)

      assert {:ok, 1, _max_ts, 0} =
               InvoiceFetcher.fetch_all("token", :expense, company.nip, company.id, from)

      correction = KsefHub.Invoices.get_invoice_by_ksef_number(company.id, "CORR-001")
      assert correction != nil
      assert correction.invoice_kind == :correction
      assert correction.corrects_invoice_id == original.id
      assert correction.corrected_invoice_ksef_number == "7831812112-20260407-5B69FA00002B-9D"
    end

    test "correction invoice remains unlinked when original does not exist yet", %{
      company: company
    } do
      correction_xml = File.read!("test/support/fixtures/sample_correction.xml")
      storage_date = DateTime.to_iso8601(DateTime.utc_now())

      KsefHub.KsefClient.Mock
      |> expect(:query_invoice_metadata, fn _token, _filters, _opts ->
        {:ok,
         %{
           invoices: [
             %{
               "ksefNumber" => "CORR-002",
               "acquisitionDate" => storage_date,
               "permanentStorageDate" => storage_date
             }
           ],
           has_more: false,
           is_truncated: false
         }}
      end)

      KsefHub.KsefClient.Mock
      |> expect(:download_invoice, fn _token, "CORR-002" ->
        {:ok, correction_xml}
      end)

      from = DateTime.add(DateTime.utc_now(), -3600)

      assert {:ok, 1, _max_ts, 0} =
               InvoiceFetcher.fetch_all("token", :expense, company.nip, company.id, from)

      correction = KsefHub.Invoices.get_invoice_by_ksef_number(company.id, "CORR-002")
      assert correction != nil
      assert correction.invoice_kind == :correction
      assert correction.corrects_invoice_id == nil
      assert correction.corrected_invoice_ksef_number == "7831812112-20260407-5B69FA00002B-9D"

      # Now insert the original and run the bulk linking
      original =
        insert(:invoice,
          company: company,
          ksef_number: "7831812112-20260407-5B69FA00002B-9D",
          type: :income
        )

      assert {1, nil} = KsefHub.Invoices.link_unlinked_corrections(company.id)

      correction = KsefHub.Invoices.get_invoice!(company.id, correction.id)
      assert correction.corrects_invoice_id == original.id
    end
  end
end
