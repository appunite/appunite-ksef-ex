# 0033. Billing Date Field

Date: 2026-03-18

## Status

Superseded by 0034

## Context

Invoices have `issue_date` and `sales_date`, but users need to assign invoices to accounting periods (months) that may differ from those dates. For example, an invoice with sales_date 2026-02-15 might need to be accounted for in March 2026. There was no way to analytically move invoices between months without changing the invoice's actual dates.

## Decision

Add a `billing_date` field (`:date`, first-of-month convention) to the invoices table:

- **Auto-defaults** from `sales_date` (falling back to `issue_date`), truncated to the first day of the month.
- **Always user-overridable** — users can set any first-of-month date regardless of the invoice's actual dates.
- **Exposed in API** — included in create, update, and show endpoints. Optional on create (auto-computed if omitted).
- **Filterable** — `billing_date_from` / `billing_date_to` filter params on the list endpoint, backed by a `(company_id, billing_date)` index.
- **LiveView** — editable as a month picker in the invoice edit form.
- **Backfill** — migration populates existing rows from `COALESCE(sales_date, issue_date)` truncated to first-of-month.

Auto-computation only happens on invoice creation and upsert. Updating `sales_date` or `issue_date` after creation does NOT recalculate `billing_date` — this preserves intentional user overrides.

## Consequences

- New nullable column with backfill migration. Rows with neither `sales_date` nor `issue_date` will have `NULL` billing_date.
- No breaking changes to existing API consumers — the field is purely additive.
- Users can now group/filter invoices by billing period independently of invoice dates, enabling month-end accounting workflows.
