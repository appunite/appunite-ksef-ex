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

      {:ok, %{invoices: headers} = result} ->
        {new_count, new_max_ts} =
          process_invoices(access_token, headers, type, nip, count, max_ts)

        next_action = decide_next_action(result, new_max_ts, max_ts)

        handle_next_action(
          next_action,
          access_token,
          type,
          nip,
          from,
          page_offset,
          new_count,
          new_max_ts
        )

      {:error, {:rate_limited, retry_after}} ->
        Logger.warning("Rate limited, waiting #{retry_after}s")
        Process.sleep(retry_after * 1000 + :rand.uniform(1000))
        do_fetch(access_token, type, nip, from, page_offset, count, max_ts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decide_next_action(%{is_truncated: true, has_more: true}, new_max_ts, old_max_ts)
       when new_max_ts == nil or new_max_ts == old_max_ts do
    :narrow_range
  end

  defp decide_next_action(%{is_truncated: true}, new_max_ts, old_max_ts)
       when new_max_ts == nil or new_max_ts == old_max_ts do
    :truncation_no_progress
  end

  defp decide_next_action(%{is_truncated: true}, _new_max_ts, _old_max_ts), do: :narrow_range
  defp decide_next_action(%{has_more: true}, _new_max_ts, _old_max_ts), do: :next_page
  defp decide_next_action(_result, _new_max_ts, _old_max_ts), do: :done

  defp handle_next_action(
         :truncation_no_progress,
         _token,
         _type,
         _nip,
         _from,
         _offset,
         _count,
         _max_ts
       ) do
    Logger.error("Truncated response with no forward progress, aborting sync")
    {:error, :truncation_no_progress}
  end

  defp handle_next_action(:narrow_range, token, type, nip, _from, _offset, count, max_ts) do
    do_fetch(token, type, nip, max_ts, 0, count, max_ts)
  end

  defp handle_next_action(:next_page, token, type, nip, from, offset, count, max_ts) do
    do_fetch(token, type, nip, from, offset + 1, count, max_ts)
  end

  defp handle_next_action(:done, _token, _type, _nip, _from, _offset, count, max_ts) do
    {:ok, count, max_ts}
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
