# 0007. Unified Invoice Model and API

Date: 2026-02-07

## Status

Accepted

## Context

KSeF Hub handles two types of invoices:

1. **Income invoices** — issued by the taxpayer (seller NIP matches the credential NIP). Synced from KSeF, read-only, used for record-keeping.
2. **Expense invoices** — received by the taxpayer (buyer NIP matches the credential NIP). Synced from KSeF, require approval/rejection workflow before passing to accounting.

Both types share the same FA(3) XML schema, the same KSeF API for retrieval, and nearly identical fields (seller, buyer, amounts, dates, KSeF reference number). The original project structure in CLAUDE.md anticipated separate controllers (`expense_controller.ex`, `income_controller.ex`), but during implementation we needed to decide whether to use separate tables/contexts or a unified model.

## Decision

We use a **single `invoices` table** with a `type` discriminator field (`"income"` or `"expense"`) and a **single unified API** via `KsefHubWeb.Api.InvoiceController`.

### Single Table Design

The `invoices` table stores both types with identical columns:

- `type` — `"income"` or `"expense"`, validated via `validate_inclusion/3`
- `status` — `"pending"`, `"approved"`, or `"rejected"` (workflow applies to expense only)
- `ksef_number` — unique constraint for deduplication across both types
- Composite index on `(type, status)` for efficient filtered queries

### Unified Context

`KsefHub.Invoices.list_invoices/1` accepts a filter map and composes an Ecto query dynamically via `Enum.reduce/3`:

```elixir
Invoices.list_invoices(%{type: "expense", status: "pending", date_from: ~D[2026-01-01]})
```

Filters supported: `type`, `status`, `seller_nip`, `buyer_nip`, `date_from`, `date_to`, `query` (text search across invoice number, seller name, buyer name).

### Type-Aware Business Logic

Approval and rejection are restricted to expense invoices via pattern matching in function heads:

```elixir
def approve_invoice(%Invoice{type: "expense"} = invoice), do: ...
def approve_invoice(%Invoice{type: type}), do: {:error, {:invalid_type, type}}
```

This enforces the business rule at the context layer, not the controller layer.

### Single API Controller

Instead of separate `IncomeController` and `ExpenseController`, one `InvoiceController` handles all operations. Consumers filter by type via query parameter:

- `GET /api/invoices?type=income` — income invoices
- `GET /api/invoices?type=expense&status=pending` — pending expense invoices
- `POST /api/invoices/:id/approve` — returns 422 if not an expense invoice

### Sync Integration

`KsefHub.Sync.InvoiceFetcher` determines the type during sync by comparing the invoice's seller/buyer NIP against the credential NIP, then passes `type: "income"` or `type: "expense"` to `Invoices.upsert_invoice/1`. The upsert uses `conflict_target: :ksef_number` — the same invoice cannot exist as both income and expense.

Alternatives considered:

- **Separate tables (`income_invoices`, `expense_invoices`)**: Enforces type separation at the database level but duplicates schema, migrations, and context functions. Cross-type queries (e.g., "all invoices from NIP X") require UNION queries.
- **Separate controllers per type**: Matches the original CLAUDE.md structure but leads to duplicated controller logic (index, show, PDF generation). The only type-specific actions (approve/reject) are better handled by pattern matching in the context.
- **Polymorphic associations**: Ecto doesn't natively support STI/polymorphism. A `type` field with validation is the idiomatic Elixir approach.

## Consequences

- **Simpler schema management**: One table, one set of migrations, one set of indexes. No schema drift between types.
- **Flexible querying**: Any combination of filters works across both types. Dashboard aggregations (`count_by_type_and_status/0`) are simple GROUP BY queries on one table.
- **Business rule enforcement via pattern matching**: The context layer guards type-specific operations. Controllers stay thin and type-agnostic.
- **Single API surface for consumers**: External systems learn one endpoint (`/api/invoices`) with filter parameters, not two separate resource paths.
- **Type field must be trusted**: The `type` field is set during sync (by NIP comparison) and validated on insert. There is no API endpoint for consumers to change an invoice's type.
- **Status field applies to both types but only matters for expense**: Income invoices stay in `"pending"` status permanently. This is a minor semantic oddity but avoids nullable fields or separate status models.
