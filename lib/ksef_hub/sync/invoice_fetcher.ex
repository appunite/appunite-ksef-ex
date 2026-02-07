defmodule KsefHub.Sync.InvoiceFetcher do
  @moduledoc """
  Handles paginated metadata queries and XML download from KSeF
  with rate limiting, truncation handling, and deduplication.
  """

  require Logger

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Parser

  @overlap_minutes 10
  @max_pages 100

  defp ksef_client, do: Application.get_env(:ksef_hub, :ksef_client, KsefHub.KsefClient.Live)

  @doc """
  Fetches all invoices for a given type since the checkpoint, downloads XML,
  parses, and upserts. Returns `{:ok, count, max_timestamp}`.
  """
  def fetch_all(access_token, type, nip, checkpoint_timestamp) do
    from = DateTime.add(checkpoint_timestamp, -@overlap_minutes * 60)

    do_fetch(access_token, type, nip, from, 0, 0, nil)
  end

  defp do_fetch(_access_token, _type, _nip, _from, page, count, max_ts)
       when page >= @max_pages do
    Logger.warning("Sync hit max page limit (#{@max_pages})")
    {:ok, count, max_ts}
  end

  defp do_fetch(access_token, type, nip, from, page_offset, count, max_ts) do
    filters = %{type: type, date_from: from}
    opts = [page_offset: page_offset, page_size: 100]

    case ksef_client().query_invoice_metadata(access_token, filters, opts) do
      {:ok, %{invoices: [], has_more: false}} ->
        {:ok, count, max_ts}

      {:ok, %{invoices: headers, has_more: has_more, is_truncated: is_truncated}} ->
        {new_count, new_max_ts} =
          process_invoices(access_token, headers, type, nip, count, max_ts)

        cond do
          is_truncated ->
            # Detect stalled progress — abort if max_ts didn't advance
            if new_max_ts == nil or new_max_ts == max_ts do
              Logger.error("Truncated response with no forward progress, aborting sync")
              {:error, :truncation_no_progress}
            else
              # Narrow date range using last record's date, reset page offset
              do_fetch(access_token, type, nip, new_max_ts, 0, new_count, new_max_ts)
            end

          has_more ->
            do_fetch(access_token, type, nip, from, page_offset + 1, new_count, new_max_ts)

          true ->
            {:ok, new_count, new_max_ts}
        end

      {:error, {:rate_limited, retry_after}} ->
        Logger.warning("Rate limited, waiting #{retry_after}s")
        Process.sleep(retry_after * 1000 + :rand.uniform(1000))
        do_fetch(access_token, type, nip, from, page_offset, count, max_ts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_invoices(access_token, headers, type, nip, count, max_ts) do
    Enum.reduce(headers, {count, max_ts}, fn header, {acc_count, acc_max_ts} ->
      ksef_number = header["ksefReferenceNumber"] || header["invoiceReferenceNumber"]

      case download_and_upsert(access_token, ksef_number, type, nip, header) do
        {:ok, invoice} ->
          new_max = pick_max_timestamp(acc_max_ts, invoice.permanent_storage_date)
          {acc_count + 1, new_max}

        {:error, reason} ->
          Logger.error("Failed to process invoice #{ksef_number}: #{inspect(reason)}")
          {acc_count, acc_max_ts}
      end
    end)
  end

  defp download_and_upsert(access_token, ksef_number, _type, nip, header) do
    with {:ok, xml} <- ksef_client().download_invoice(access_token, ksef_number),
         {:ok, parsed} <- Parser.parse(xml) do
      invoice_type = Parser.determine_type(parsed, nip)

      attrs =
        Map.merge(parsed, %{
          ksef_number: ksef_number,
          type: invoice_type,
          xml_content: xml,
          ksef_acquisition_date: parse_header_date(header["acquisitionTimestamp"]),
          permanent_storage_date: parse_header_date(header["permanentStorageDate"])
        })
        |> Map.drop([:line_items])

      Invoices.upsert_invoice(attrs)
    end
  end

  defp parse_header_date(nil), do: nil

  defp parse_header_date(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp pick_max_timestamp(nil, new), do: new
  defp pick_max_timestamp(old, nil), do: old

  defp pick_max_timestamp(old, new) do
    if DateTime.compare(new, old) == :gt, do: new, else: old
  end
end
