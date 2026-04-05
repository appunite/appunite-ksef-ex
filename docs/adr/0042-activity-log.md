# 0042. Activity Log System

Date: 2026-04-05

## Status

Accepted

## Context

The platform had no audit trail for user and system actions. Two needs drove this work:

1. **Invoice activity timeline** — users want to see the full history of an invoice (who approved it, when classification changed, when a comment was added) directly on the invoice detail page.
2. **Platform audit log** — admins need visibility into company-wide operations (team changes, credential uploads, API token management, sync triggers) for security and compliance.

The main architectural challenge was **making event emission automatic and hard to forget**. With 40+ operations to track across 8 contexts, any approach requiring developers to manually call logging functions would be error-prone and create code pollution.

### Approaches considered

| Approach | Verdict |
|----------|---------|
| Direct `AuditLog.log()` calls in context functions | Rejected — pollutes business logic, easy to forget |
| Manual `Events.*` helper calls per operation | Rejected (initial approach, later replaced) — still requires developer to remember |
| Ecto.Multi (wrap mutation + log in same transaction) | Rejected — forces every function to know about logging |
| Telemetry events | Rejected — designed for metrics, unergonomic for domain events |
| **Trackable behaviour + TrackedRepo wrapper** | **Accepted** — schema owns event classification, TrackedRepo handles emission automatically |

## Decision

### Core pattern: Trackable behaviour on schemas

Each Ecto schema that participates in activity logging implements the `Trackable` behaviour, defining a `track_change/1` callback that inspects the changeset and returns `{action, metadata}` or `:skip`. The schema **owns the mapping** from data changes to domain events.

```elixir
# In the schema module:
@behaviour KsefHub.ActivityLog.Trackable

@impl true
def track_change(%Ecto.Changeset{action: :insert} = cs) do
  {"invoice.created", %{source: to_string(get_field(cs, :source))}}
end

def track_change(%Ecto.Changeset{} = changeset) do
  case Enum.find(@tracked_fields, &Map.has_key?(changeset.changes, &1)) do
    :status -> {"invoice.status_changed", %{old: ..., new: ...}}
    :is_excluded -> {if(cs.changes.is_excluded, do: "invoice.excluded", else: "invoice.included"), %{}}
    nil -> {"invoice.updated", %{changed_fields: ...}}
  end
end
```

### TrackedRepo: automatic event emission

`TrackedRepo` wraps `Repo.insert/update/delete`. On success, it calls `schema.track_change(changeset)` to derive the event. The developer doesn't specify action names — the schema figures it out from the changeset.

```
Context function
  → build changeset
  → TrackedRepo.update(changeset, opts)
    → Repo.update(changeset)
    → schema.track_change(changeset) → {action, metadata}
    → Events.emit(event)
      → [prod] PubSub.broadcast → Recorder GenServer → DB
      → [test] TestEmitter → send(test_pid, event)
```

**No-op detection** is built into TrackedRepo: if `changeset.changes == %{}`, the update succeeds but no event is emitted.

### Context functions are 2-3 lines

```elixir
def approve_invoice(%Invoice{} = invoice, opts \\ []) do
  invoice
  |> Invoice.changeset(%{status: :approved})
  |> TrackedRepo.update(opts)
end

def delete_category(%Category{} = category, opts \\ []) do
  TrackedRepo.delete(category, opts)
end
```

### Schemas implementing Trackable

| Schema | Events classified |
|--------|-------------------|
| `Invoice` | created, status_changed, excluded/included, duplicate_*, classification_changed (category/tags/cost_line/project_tag), note_updated, billing_date_changed, access_changed, updated (catch-all) |
| `Category` | created, updated, deleted |
| `CompanyBankAccount` | created, updated, deleted |
| `Membership` | role_changed, member_blocked/unblocked, member_removed |
| `PaymentRequest` | created, paid, voided, updated |
| `ApiToken` | generated, revoked |
| `Credential` | uploaded (insert), invalidated (deactivation) |

### Manual Events calls (structurally necessary)

Some events can't use TrackedRepo because they have no changeset or involve Multi transactions:

| Event | Why manual |
|-------|-----------|
| `invoice.comment_added/edited/deleted` | InvoiceComment lacks `company_id`, needs cross-entity lookup |
| `invoice.access_granted/access_revoked` | `on_conflict: :nothing` makes TrackedRepo awkward |
| `invoice.downloaded` | Controller-level, no changeset |
| `invoice.public_link_generated` | Atomic `update_all` in generate_public_token, no changeset |
| `invoice.re_extraction_triggered` | Triggered from LiveView, no DB mutation |
| `credential.uploaded` (in replace) | Multi.insert bypasses TrackedRepo |
| `export.created` | Multi transaction |
| `export.downloaded` | Controller-level, no changeset |
| `team.invitation_sent/invitation_accepted` | Multi transaction |
| `sync.triggered/completed` | Oban job, no changeset |
| `user.logged_in/logged_out` | Session management, no Ecto mutation |

These use `Events.*` helper functions directly. The `Events` module contains **only** these helpers plus the `emit/1` dispatch point — no dead code.

### Schema: extended `audit_logs` table

Added to the existing (previously unused) table:
- `company_id` — FK to companies, multi-tenant scoping
- `actor_type` — `"user"` | `"system"` | `"api"`
- `actor_label` — denormalized actor name

### Configurable emitter for testing

`Events.emit/1` dispatches through `Application.get_env(:ksef_hub, :activity_log_emitter)`:
- **Production**: PubSub broadcast (default) → Recorder GenServer → DB
- **Test**: `TestEmitter` sends directly to test process → `assert_received` (synchronous, deterministic)

The `TestEmitter` uses process dictionary + `$callers` chain for `async: true` safety.

### Recorder crash resilience

The Recorder GenServer wraps persistence in `try/rescue` so Ecto errors are logged but never crash the process. Supervised with automatic restart.

## Consequences

### Positive

- **Automatic** — developers use `TrackedRepo` and the schema handles events. No manual logging to forget.
- **Schema owns classification** — adding a new tracked field means adding one `classify_field/2` clause. Single responsibility.
- **Clean contexts** — most operations are 2-3 lines. No event boilerplate.
- **No-op safe** — TrackedRepo skips events when changeset has no changes
- **Testable** — `assert_received`/`refute_received` with zero delay
- **Fire-and-forget** — no latency impact on user operations
- **Real-time UI** — invoice timeline updates via PubSub

### Negative

- **Eventual consistency** — brief window between operation and audit record
- **Event loss on crash** — in-flight PubSub messages lost if BEAM crashes. Acceptable for audit log.
- **Multi gap** — `Repo.transaction` with `Ecto.Multi` bypasses TrackedRepo. These paths need manual `Events.*` calls.
- **No compile-time enforcement** — a developer *can* use `Repo.update` directly and skip events. `TrackedRepo` makes the right thing easy but doesn't prevent the wrong thing. Code review catches this.

### Future considerations

- **Retention policy** — Oban cron job to prune entries older than 12 months
- **Table partitioning** — range partitioning by `inserted_at` if >10M rows
- **Multi-aware TrackedRepo** — extend TrackedRepo to wrap Ecto.Multi steps, eliminating the remaining manual Events calls
- **Deferred emission** — defer `maybe_emit` until after transaction commit (requires Ecto `after_transaction` from a future version or a custom wrapper)
