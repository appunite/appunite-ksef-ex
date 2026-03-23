# 0034. Billing Date Range (Multi-Month Cost Allocation)

Date: 2026-03-23

## Status

Accepted

## Context

ADR 0033 introduced a single `billing_date` field for assigning invoices to accounting periods. However, some invoices cover multiple months (e.g., quarterly service contracts = 1 invoice for 3 months). With a single date, the entire cost lands in one month, making financial reports inaccurate.

## Decision

Replace `billing_date` with `billing_date_from` and `billing_date_to` (both first-of-month dates):

- **Single-month invoices:** `billing_date_from == billing_date_to` (backward-compatible behavior).
- **Multi-month invoices:** `billing_date_from < billing_date_to`, with `net_amount / month_count` allocated proportionally to each month in the range.
- **Rounding:** First N-1 months get `round(amount / count, 2)`, last month gets the remainder to ensure the total is exact.
- **Auto-defaults:** If neither field is provided on create/upsert, both are set to the same auto-computed month from `sales_date`/`issue_date` (same logic as ADR 0033).
- **Validation:** `billing_date_to >= billing_date_from` when both present. Both must be first-of-month.
- **Filter semantics:** Changed from exact range to overlap — `billing_date_from` filter returns invoices whose `billing_date_to >= filter_value`, and vice versa.
- **Aggregation:** `expense_monthly_totals`, `expense_by_category`, and `income_monthly_summary` now expand multi-month invoices into per-month allocations in Elixir before grouping.
- **Migration:** Backfill copies `billing_date` into both new columns, then drops the old column.

## Consequences

- Breaking API change: `billing_date` field replaced by `billing_date_from` and `billing_date_to` in all request/response schemas.
- Dashboard charts automatically show proportional costs for multi-month invoices without any chart-level changes.
- Aggregation queries now fetch raw rows and expand in Elixir rather than using `GROUP BY` in SQL. This is acceptable for the expected data volumes.
- Existing single-month invoices work identically — `from == to` produces the same behavior as the old single field.
