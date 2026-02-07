# 0003. Incremental Invoice Sync with Oban

Date: 2026-02-07

## Status

Accepted

## Context

KSeF Hub needs to periodically poll the KSeF API for new invoices (both income and expense) and store them locally. Requirements:

1. Sync every 15 minutes without manual intervention
2. Survive application restarts without losing sync progress or re-processing everything
3. Respect KSeF rate limits: 8 req/s for invoice download, 2 req/s for metadata queries
4. Handle KSeF pagination quirks — truncated result sets require narrowing the date range rather than simply advancing pages
5. Deduplicate invoices (KSeF may return overlapping results)
6. Update the LiveView admin UI in real-time when sync completes

## Decision

### Job Scheduling: Oban with Cron Plugin

We use **Oban** (`~> 2.18`) instead of a bare GenServer for job scheduling:

```elixir
# config/config.exs
config :ksef_hub, Oban,
  repo: KsefHub.Repo,
  plugins: [{Oban.Plugins.Cron,
    crontab: [{"*/15 * * * *", KsefHub.Sync.SyncWorker}]}],
  queues: [sync: 1, default: 5]
```

`KsefHub.Sync.SyncWorker` (`use Oban.Worker, queue: :sync, max_attempts: 3`) implements `perform/1`. The `sync: 1` queue concurrency ensures only one sync runs at a time.

### Incremental Sync: Checkpoint-Based

Each sync type (income/expense) per NIP maintains a checkpoint (`KsefHub.Sync.Checkpoint` schema, `sync_checkpoints` table) tracking `last_seen_timestamp`:

- On first sync, look back 90 days (`@default_lookback_days`)
- On subsequent syncs, query from `last_seen_timestamp - 10 minutes` (`@overlap_minutes`). The 10-minute overlap ensures no invoices are missed due to clock skew or KSeF processing delays
- After processing all pages, advance the checkpoint to the maximum `permanent_storage_date` seen
- Checkpoint upsert uses `on_conflict: {:replace, [...]}` with `conflict_target: [:checkpoint_type, :nip]`

### Pagination and Truncation

`KsefHub.Sync.InvoiceFetcher` handles KSeF's pagination model:

- Query metadata pages with `page_size: 100`, incrementing `page_offset`
- When KSeF returns `is_truncated: true`, the result set is too large for the date range — narrow the range using the last record's timestamp and reset offset to 0
- When `has_more: true`, increment page offset normally
- Safety limit of 100 pages (`@max_pages`) prevents infinite loops
- Rate-limit responses (`{:error, {:rate_limited, retry_after}}`) trigger a sleep with jitter before retry

### Deduplication: Upsert by ksef_number

Invoices are upserted via `Invoices.upsert_invoice/1` using a unique constraint on `ksef_number`. The checkpoint overlap and pagination restarts may produce duplicate invoice references — the upsert silently handles these.

### Real-Time UI Updates: PubSub

On sync completion, the worker broadcasts via Phoenix PubSub:

```elixir
Phoenix.PubSub.broadcast(KsefHub.PubSub, "sync:status", {:sync_completed, stats})
```

LiveView pages subscribe to this topic and update without polling.

Alternatives considered:

- **GenServer with `Process.send_after`**: Simpler but loses scheduled jobs on crash/restart. No built-in retry, no persistence, no visibility into job history.
- **Webhook-based sync**: KSeF does not offer reliable webhooks for new invoice notifications. Even if it did, polling provides a reliable baseline.
- **Full re-sync each time**: Too slow and wasteful — the invoice count grows over time, and KSeF rate limits make full scans take minutes to hours.
- **Quantum (cron library)**: Lighter than Oban but lacks database-backed persistence, retry logic, and job introspection.

## Consequences

- **Oban dependency**: Adds `oban_jobs` table and Oban migrations to the database. This is a well-maintained library with broad Elixir ecosystem adoption.
- **Durable job queue**: Scheduled and in-progress jobs survive application restarts. If a sync fails mid-way, Oban retries up to 3 times with backoff.
- **Checkpoint overlap trades redundancy for completeness**: The 10-minute overlap means some invoices are re-fetched on each sync, but the upsert makes this a no-op. This is preferable to missing invoices due to timing edge cases.
- **Single sync worker concurrency**: `queues: [sync: 1]` ensures no concurrent syncs for the same NIP, avoiding KSeF's one-session-per-NIP constraint and duplicate work.
- **Job observability**: Oban stores job results in metadata (`income_count`, `expense_count` or `error`), providing a built-in audit trail of sync history.
