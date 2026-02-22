# 0018. Manual Invoice Creation with Duplicate Detection

Date: 2026-02-23

## Status

Accepted

## Context

KSeF Hub currently creates invoices only through automated KSeF sync. External systems need to register invoices that exist outside KSeF — for example when KSeF is down and companies exchange invoices by email, or when importing from other ERPs. We need a way to create invoices manually via the API while detecting potential duplicates when the same invoice later appears through KSeF sync.

## Decision

We add a `POST /api/invoices` endpoint for manual invoice creation with the following design:

**Source tracking**: A `source` field (`"ksef"` or `"manual"`) tracks invoice origin. KSeF-synced invoices require `xml_content`; manual invoices require `buyer_nip`, `buyer_name`, `net_amount`, and `gross_amount`.

**Duplicate detection**: When a manual invoice includes a `ksef_number` that already exists for the same company, the new invoice is automatically flagged as a `"suspected"` duplicate with a reference (`duplicate_of_id`) to the original. The later-added document is always the one marked as duplicate.

**Partial unique index**: The unique constraint on `(company_id, ksef_number)` is changed to a partial index excluding rows where `duplicate_of_id IS NOT NULL`. This allows duplicate invoices to coexist in the database while keeping the upsert path working for sync.

**Duplicate review**: Two new endpoints allow humans to review duplicates:
- `POST /api/invoices/:id/confirm-duplicate` — confirms the duplicate
- `POST /api/invoices/:id/dismiss-duplicate` — dismisses the duplicate flag

**Nullable xml_content**: Since manual invoices don't have FA(3) XML, `xml_content` is made nullable. The `xml`, `html`, and `pdf` endpoints return 422 when called on invoices without XML content.

## Consequences

- External systems can register invoices via a clean REST API without needing FA(3) XML
- Duplicate detection is automatic but non-destructive — human review is always required
- The partial unique index is more complex but avoids data loss from silent deduplication
- Existing sync/upsert behavior is preserved through the partial index
- `xml_content` being nullable means XML/PDF/HTML endpoints must handle the nil case
