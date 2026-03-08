# 0031. Track Invoice Creator

Date: 2026-03-08

## Status

Accepted

## Context

Invoices have a `source` field (`:ksef`, `:manual`, `:pdf_upload`, `:email`) but don't track which user created them. For audit and usability, the invoice detail page should show who added the invoice.

## Decision

- Add a nullable `created_by_id` FK on invoices referencing users. Set for manual and PDF upload paths where a user acts; nil for KSeF sync and email (system-initiated).
- Use the existing `InboundEmail.belongs_to :invoice` relationship inversely (`has_one :inbound_email` on Invoice) to resolve the email sender at display time without denormalization.
- Display a single "Added by" row combining source and creator: e.g. "Jan Kowalski (PDF upload)", "KSeF (automatic sync)", "sender@example.com (email)".
- Only show on the authenticated invoice detail page; the public page omits it for privacy.

## Consequences

- Two additional LEFT JOINs on invoice detail queries (`:created_by`, `:inbound_email`). Negligible overhead for single-record lookups.
- No data migration needed — existing invoices have `created_by_id` as nil, which falls back to the source label.
- Email sender resolution depends on the inbound_email record being present; if it's deleted, the label falls back to "Email".
