# 0037. Cost Line

Date: 2026-03-31

## Status

Accepted

## Context

Invoices have categories for ML-driven classification, but the business also needs to attribute expenses to broader cost centers (e.g., Growth, Heads, Service) for financial reporting and budgeting. These cost centers are a fixed, small set of values — distinct from the open-ended category system.

## Decision

Add a `cost_line` enum field directly on the invoices table with a fixed set of values: `growth`, `heads`, `service`, `service_delivery`, `client_success`.

- **Expense-only** — income invoices cannot have a cost line. Enforced at the context layer (`set_invoice_cost_line/2` returns `{:error, :expense_only}` for income).
- **Category integration** — categories have a `default_cost_line` field. When a category is assigned to an invoice, its default cost line is auto-applied. Users can override independently.
- **Dedicated Ecto.Enum module** (`KsefHub.Invoices.CostLine`) — provides `cast/1`, `label/1`, `values/0`, and `options/0` for forms.
- **Database constraint** — check constraint ensures only valid enum values or NULL.
- **API** — settable via `PUT /invoices/:id/category` as an optional `cost_line` parameter alongside `category_id`.
- **UI** — dropdown in the classify page, badge display on show page.

## Consequences

- Fixed enum means adding a new cost line requires a migration and code change. Acceptable given these are stable business cost centers.
- Stored as a string column with a check constraint rather than a Postgres enum, allowing easier future modifications.
- Cost line can be set independently of category, giving users flexibility in classification workflows.
