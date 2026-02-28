defmodule KsefHub.Sync.InvoiceFetcher do
  @moduledoc """
  Handles paginated metadata queries and XML download from KSeF
  with rate limiting, truncation handling, and deduplication.
  """

  require Logger

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Parser
  alias KsefHub.Sync.Checkpoint

  @overlap_minutes 10
  @max_pages 100
  # KSeF production limits dateRange to 3 months; stay safely under
  @max_range_days 89

  @spec ksef_client() :: module()
  defp ksef_client, do: Application.get_env(:ksef_hub, :ksef_client, KsefHub.KsefClient.Live)

  @doc """
  Fetches all invoices for a given type since the checkpoint, downloads XML,
  parses, and upserts. Returns `{:ok, count, max_timestamp, failed_count}`.
  """
  @spec fetch_all(
          String.t(),
          Checkpoint.checkpoint_type(),
          String.t(),
          Ecto.UUID.t(),
          DateTime.t()
        ) ::
          {:ok, non_neg_integer(), DateTime.t() | nil, non_neg_integer()} | {:error, term()}
  def fetch_all(access_token, type, nip, company_id, checkpoint_timestamp) do
    from = DateTime.add(checkpoint_timestamp, -@overlap_minutes * 60)
    earliest_allowed = DateTime.add(DateTime.utc_now(), -@max_range_days * 86_400)
    from = pick_max_timestamp(from, earliest_allowed) || from

    ctx = %{token: access_token, type: type, nip: nip, company_id: company_id}
    do_fetch(ctx, from, 0, 0, 0, nil)
  end

  @spec do_fetch(
          map(),
          DateTime.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          DateTime.t() | nil
        ) ::
          {:ok, non_neg_integer(), DateTime.t() | nil, non_neg_integer()} | {:error, term()}
  defp do_fetch(_ctx, _from, page, count, failed, max_ts) when page >= @max_pages do
    Logger.warning("Sync hit max page limit (#{@max_pages})")
    {:ok, count, max_ts, failed}
  end

  defp do_fetch(ctx, from, page_offset, count, failed, max_ts) do
    date_to = DateTime.utc_now()
    filters = %{type: ctx.type, date_from: from, date_to: date_to}
    opts = [page_offset: page_offset, page_size: 100]

    case ksef_client().query_invoice_metadata(ctx.token, filters, opts) do
      {:ok, %{invoices: [], has_more: false}} ->
        {:ok, count, max_ts, failed}

      {:ok, %{invoices: headers} = result} ->
        {new_count, new_failed, new_max_ts} =
          process_invoices(ctx, headers, count, failed, max_ts)

        next_action = decide_next_action(result, new_max_ts, max_ts)
        handle_next_action(next_action, ctx, from, page_offset, new_count, new_failed, new_max_ts)

      {:error, {:rate_limited, retry_after}} ->
        Logger.warning("Rate limited, waiting #{retry_after}s")
        Process.sleep(retry_after * 1000 + :rand.uniform(1000))
        do_fetch(ctx, from, page_offset, count, failed, max_ts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec decide_next_action(map(), DateTime.t() | nil, DateTime.t() | nil) ::
          :narrow_range | :truncation_no_progress | :next_page | :done
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

  @spec handle_next_action(
          atom(),
          map(),
          DateTime.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          DateTime.t() | nil
        ) ::
          {:ok, non_neg_integer(), DateTime.t() | nil, non_neg_integer()} | {:error, term()}
  defp handle_next_action(:truncation_no_progress, _ctx, _from, _offset, _count, _failed, _max_ts) do
    Logger.error("Truncated response with no forward progress, aborting sync")
    {:error, :truncation_no_progress}
  end

  defp handle_next_action(:narrow_range, _ctx, _from, _offset, _count, _failed, nil) do
    Logger.error("Cannot narrow range: max_ts is nil")
    {:error, :truncation_no_progress}
  end

  defp handle_next_action(:narrow_range, ctx, _from, _offset, count, failed, max_ts) do
    do_fetch(ctx, max_ts, 0, count, failed, max_ts)
  end

  defp handle_next_action(:next_page, ctx, from, offset, count, failed, max_ts) do
    do_fetch(ctx, from, offset + 1, count, failed, max_ts)
  end

  defp handle_next_action(:done, _ctx, _from, _offset, count, failed, max_ts) do
    {:ok, count, max_ts, failed}
  end

  @spec process_invoices(map(), [map()], non_neg_integer(), non_neg_integer(), DateTime.t() | nil) ::
          {non_neg_integer(), non_neg_integer(), DateTime.t() | nil}
  defp process_invoices(ctx, headers, count, failed, max_ts) do
    Enum.reduce(headers, {count, failed, max_ts}, fn header,
                                                     {acc_count, acc_failed, acc_max_ts} ->
      ksef_number = header["ksefNumber"]

      case download_and_upsert(ctx, ksef_number, header) do
        {:ok, invoice, :inserted} ->
          new_max = pick_max_timestamp(acc_max_ts, invoice.permanent_storage_date)
          {acc_count + 1, acc_failed, new_max}

        {:ok, invoice, :updated} ->
          new_max = pick_max_timestamp(acc_max_ts, invoice.permanent_storage_date)
          {acc_count, acc_failed, new_max}

        {:error, reason} ->
          Logger.error("Failed to process invoice #{ksef_number}: #{inspect(reason)}")
          {acc_count, acc_failed + 1, acc_max_ts}
      end
    end)
  end

  @spec download_and_upsert(map(), String.t() | nil, map()) ::
          {:ok, Invoices.Invoice.t(), :inserted | :updated} | {:error, term()}
  defp download_and_upsert(ctx, ksef_number, header) do
    with {:ok, xml} <- ksef_client().download_invoice(ctx.token, ksef_number),
         {:ok, parsed} <- Parser.parse(xml) do
      invoice_type = Parser.determine_type(parsed, ctx.nip)

      attrs =
        Map.merge(parsed, %{
          ksef_number: ksef_number,
          type: invoice_type,
          xml_content: xml,
          company_id: ctx.company_id,
          ksef_acquisition_date: parse_header_date(header["acquisitionDate"]),
          permanent_storage_date: parse_header_date(header["permanentStorageDate"])
        })
        |> Map.drop([:line_items])

      attrs =
        Map.put(attrs, :extraction_status, Invoices.determine_extraction_status_from_attrs(attrs))

      Invoices.upsert_invoice(attrs)
    end
  end

  @spec parse_header_date(String.t() | nil) :: DateTime.t() | nil
  defp parse_header_date(nil), do: nil

  defp parse_header_date(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  @spec pick_max_timestamp(DateTime.t() | nil, DateTime.t() | nil) :: DateTime.t() | nil
  defp pick_max_timestamp(nil, new), do: new
  defp pick_max_timestamp(old, nil), do: old

  defp pick_max_timestamp(old, new) do
    if DateTime.compare(new, old) == :gt, do: new, else: old
  end
end
