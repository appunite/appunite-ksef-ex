# 0015. Invoice Pagination & Search Indexes

Date: 2026-02-12

## Status

Accepted

## Context

`Invoices.list_invoices/2` loaded the entire invoice set for a company into memory with no LIMIT/OFFSET. Both the REST API and LiveView UI used this function directly. As the invoice count grows (thousands per company from KSeF sync), this would degrade response times, increase memory usage, and eventually cause OOM errors.

Additionally, the ILIKE search across `invoice_number`, `seller_name`, and `buyer_name` had no supporting indexes, resulting in sequential scans on every search query. The `xml_content` text field (potentially large FA(3) XML) was also loaded unnecessarily in list queries.

## Decision

### Offset-based pagination

We chose offset-based pagination (LIMIT/OFFSET) over cursor-based pagination because:

- Simpler implementation — fits naturally with page number URLs
- Users need random page access (jump to page 5, not just "next")
- Invoice lists are filtered and sorted by `issue_date DESC` — a stable sort order
- Expected dataset size per company (low thousands) makes offset performance acceptable

The context exposes `list_invoices_paginated/2` which returns a map with `entries`, `page`, `per_page`, `total_count`, and `total_pages`. This uses a two-query approach (count + data) rather than SQL window functions to keep queries simple and composable with existing filters.

Defaults: page 1, per_page 25, max per_page 100.

### xml_content exclusion

List queries now use `select([i], struct(i, ^@list_fields))` to exclude `xml_content`. This field is only needed for single-invoice views (show, HTML preview, PDF generation) which use `get_invoice!/2`.

### pg_trgm indexes for ILIKE search

We enabled the `pg_trgm` extension and added GIN trigram indexes on `invoice_number`, `seller_name`, and `buyer_name`. This allows PostgreSQL to use index scans for `ILIKE '%pattern%'` queries instead of sequential scans.

### Compound indexes

- `(company_id, issue_date, inserted_at)` — serves the default ORDER BY clause
- `(company_id, type, status)` — serves filtered listings

## Consequences

- All invoice list views are now paginated (API and LiveView)
- API response shape changed: `{data: [...], meta: {page, per_page, total_count, total_pages}}` — clients consuming the API must handle the `meta` key
- Two database queries per page load (count + data) — acceptable for the expected dataset sizes
- `xml_content` is nil in list results — code that accesses `xml_content` from list queries will need to use `get_invoice!/2` instead
- pg_trgm extension must be available on the database (included by default on Supabase)
- If cursor-based pagination is needed in the future (e.g., for very large datasets or real-time sync consumers), it can be added as a separate function without changing the existing paginated interface
