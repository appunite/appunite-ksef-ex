# 0032. Block Invoice Data Editing for KSeF-Sourced Invoices

Date: 2026-03-18

## Status

Accepted

## Context

KSeF invoices are government-approved, legally immutable documents fetched from the Polish National e-Invoice System. Modifying their data fields (amounts, dates, NIPs, names) after download would create a divergence between our records and the official government source. Only correction invoices issued through KSeF can legally alter invoice data.

Non-KSeF sources (manual entry, PDF upload, email) may contain OCR or LLM extraction errors that users need to fix.

Meanwhile, internal properties like category, tags, notes, comments, and approval status are our system metadata — not part of the invoice document itself — and must remain editable regardless of source.

## Decision

Block editing of invoice data fields for KSeF-sourced invoices at three layers:

1. **Schema** — `Invoice.data_editable?/1` predicate returns `false` for `:ksef` source. `edit_changeset/2` rejects edits with an error changeset for KSeF invoices.
2. **Context** — `Invoices.update_invoice_fields/2` returns `{:error, :ksef_not_editable}` for KSeF invoices.
3. **Web** — LiveView hides the edit button and shows a lock badge; API controller returns 422 for PATCH on KSeF invoices.

Internal metadata operations (`set_invoice_category`, `set_invoice_tags`, `update_invoice_note`, `approve_invoice`, `reject_invoice`) are unaffected and work for all sources.

As a side effect, the API update endpoint was broadened from allowing only `pdf_upload` to allowing all non-KSeF sources (manual, pdf_upload, email).

## Consequences

- KSeF invoice data is immutable in the system, matching legal requirements.
- Users can still correct OCR/extraction errors on non-KSeF invoices.
- Categories, tags, notes, comments, and approval workflows work identically for all sources.
- Three-layer defense-in-depth means a bug in one layer cannot bypass the restriction.
- Future sources added to the `source` enum will be editable by default — only `:ksef` is blocked.
