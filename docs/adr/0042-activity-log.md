# 0042. Activity Log System

Date: 2026-04-05

## Status

Accepted

## Context

The platform had no audit trail for user and system actions. There was an unused `AuditLog` schema with basic fields (`action`, `resource_type`, `resource_id`, `metadata`, `user_id`, `ip_address`) but zero callers. Two distinct needs drove this work:

1. **Invoice activity timeline** — users want to see the full history of an invoice (who approved it, when classification changed, when a comment was added) directly on the invoice detail page.
2. **Platform audit log** — admins need visibility into company-wide operations (team changes, credential uploads, API token management, sync triggers) for security and compliance.

The main architectural challenge was **avoiding code pollution**. With 40+ operations to track across 8 contexts, naively sprinkling `AuditLog.log()` calls everywhere would create tight coupling, make contexts harder to read, and be easy to forget when adding new operations.

### Approaches considered

| Approach | Verdict |
|----------|---------|
| Direct `AuditLog.log()` calls in every context function | Rejected — pollutes business logic, tight coupling, easy to forget |
| Ecto.Multi (wrap mutation + log in same transaction) | Rejected — forces every context function to know about logging, bloats already-large contexts |
| Telemetry events | Rejected — designed for metrics, unergonomic for rich domain events with metadata |
| Ecto repo callbacks | Rejected — too low-level, can't capture domain intent ("approved" vs "status changed to approved") |
| **PubSub event bus + Recorder GenServer** | **Accepted** — clean separation, already used in the codebase for sync status |

## Decision

### Architecture: PubSub event bus with configurable emitter

Context functions emit domain events after successful operations. A Recorder GenServer subscribes to the PubSub topic and persists events to the `audit_logs` table asynchronously. The emission step is configurable via application config, allowing tests to use a synchronous `TestEmitter` instead of PubSub.

```
Context function
  → Events.invoice_status_changed(invoice, :pending, :approved, opts)
    → Events.emit(event_struct)
      → [prod] Phoenix.PubSub.broadcast("activity_log", {:activity_event, event})
        → Recorder GenServer → AuditLog.log() → DB
        → Recorder → PubSub.broadcast("activity:invoice:<id>", {:new_activity, log})
          → LiveView handle_info → prepend to @activity_log assign
      → [test] TestEmitter → send(test_pid, {:activity_event, event})
        → assert_received in test (synchronous, no Process.sleep)
```

### Schema: extend existing `audit_logs` table

Added three columns to the existing unused table:
- `company_id` — FK to companies, enables multi-tenant scoping
- `actor_type` — `"user"` | `"system"` | `"api"`, distinguishes human from automated actions
- `actor_label` — denormalized actor name (self-contained even if user is deleted)

Composite indexes for the two primary query patterns:
- `(company_id, resource_type, resource_id, inserted_at)` — invoice timeline
- `(company_id, inserted_at)` — platform activity log

### Integration pattern: context-side broadcasting with optional `opts`

Events are broadcast **inside context functions** on success. Each function accepts an optional `opts \\ []` keyword list for caller-provided actor info (`user_id`, `actor_label`, `actor_type`, `ip_address`). LiveView handlers pass `actor_opts(socket)` to provide user context.

```elixir
# In context
def approve_invoice(invoice, opts \\ []) do
  case update_invoice(invoice, %{status: :approved}) do
    {:ok, updated} ->
      Events.invoice_status_changed(updated, old_status, :approved, opts)
      {:ok, updated}
    error -> error
  end
end

# In LiveView
Invoices.approve_invoice(invoice, actor_opts(socket))
```

### No-op detection

Events are suppressed when nothing actually changed:
- `changeset.changes != %{}` check for note and billing date updates
- Value comparison (`old_value != new_value`) for category, tags, cost_line, project_tag
- Pattern-matched guards: `defp maybe_log_category_change(_, same, same, _), do: :ok`

### Crash resilience

The Recorder GenServer wraps persistence in `try/rescue` so Ecto errors (e.g., invalid UUID types) are logged but never crash the process. The Recorder is supervised with automatic restart.

### Test infrastructure

A `TestEmitter` module replaces PubSub in test config. It stores the test process PID in the process dictionary and walks the `$callers` chain for async-safe delivery. Tests use `assert_received`/`refute_received` — fully synchronous, zero-delay, deterministic.

## Consequences

### Positive

- **Clean separation** — contexts have minimal coupling to the activity log (one-line `Events.*` call per operation)
- **Fire-and-forget** — no latency impact on user operations; persistence happens asynchronously
- **Real-time UI** — invoice timeline updates via PubSub when another user makes changes
- **Testable** — configurable emitter enables synchronous assertions without touching the DB
- **No-op safe** — activity log isn't polluted with meaningless "changed X to same value" entries
- **Multi-tenant** — all queries scoped by `company_id`

### Negative

- **Eventual consistency** — brief window between operation and audit record appearing (PubSub delivery + DB insert)
- **Event loss on node crash** — in-flight PubSub messages are lost if the BEAM VM crashes between emit and persist. Acceptable for an activity log (not a financial ledger)
- **Schema coupling** — the `Events` module has knowledge of every domain resource's fields (id, company_id). Adding a new resource type requires a new event function
- **Verbose Events module** — 44 public functions with similar patterns. Kept explicit over macros for greppability and per-function documentation

### Future considerations

- **Retention policy** — add an Oban cron job to prune entries older than 12 months
- **Table partitioning** — consider range partitioning by `inserted_at` if the table exceeds ~10M rows
- **Invoice creation events** — not yet wired due to multiple complex code paths (KSeF sync, manual, PDF upload, email). Should be added per-path when those areas are next touched
- **Download tracking** — requires wiring in the controller layer (file serving), not yet done
