# 0020. PDF Invoice Upload Flow

Date: 2026-02-24

## Status

Accepted

## Context

Users add non-KSeF invoices manually via `POST /api/invoices` by providing all fields as JSON. This is tedious for expense invoices that already exist as PDF files. The au-ksef-unstructured sidecar (ADR 0017) can extract structured data from PDF files automatically.

We need a way to upload a PDF, extract data, and create an invoice in a single step. If extraction misses required fields, the invoice should still be created but marked as needing review.

## Decision

### New source: `pdf_upload`

Add `"pdf_upload"` as a third source value alongside `"ksef"` and `"manual"`. This provides distinct provenance — pdf_upload invoices were created from an uploaded PDF, not hand-entered or synced.

### PDF stored in DB

Store the original PDF as a `binary` column (`pdf_content`) in the invoices table, parallel to how `xml_content` stores FA(3) XML for KSeF invoices. Both are excluded from list queries via `@list_fields`.

### Extraction status tracking

A new `extraction_status` field tracks extraction quality:
- `"complete"` — all critical fields extracted (seller_nip, seller_name, invoice_number, issue_date, net_amount, gross_amount)
- `"partial"` — some critical fields missing
- `"failed"` — extraction service returned an error

### Relaxed validation for pdf_upload

The changeset validation is source-specific:
- `ksef` requires xml_content + core fields
- `manual` requires core fields + buyer fields + amounts
- `pdf_upload` requires only pdf_content

This means partial-extraction invoices can be created despite missing fields.

### Approval guard

Invoices with `extraction_status: "partial"` cannot be approved. Users must fill in missing fields via PATCH first, which recalculates the extraction status.

### Synchronous extraction

Extraction is synchronous in the initial implementation. This is simpler than async and avoids polling/notification complexity. If the service fails, the invoice is still created with `extraction_status: "failed"`.

**Mitigations and future evolution:**

1. **Timeout** — start with a timeout based on measured 95th-percentile latency (target 30-45s). The current 120s ceiling is a safety bound, not an SLO.
2. **Async path** — if synchronous extraction proves too slow or ties up connections, move to accepting uploads with `202 Accepted`, enqueuing extraction in an Oban job, and letting clients poll `extraction_status`.
3. **Concurrency cap** — add an upload-route concurrency limit or rate-limit to bound simultaneous extractions and protect downstream resources.

See ADR 0021 for the related storage refactoring that would complement an async design.

### PDF download behavior

- `GET /pdf` — serves original uploaded PDF (no XML-based generation)
- `GET /xml` — returns 422 (pdf_upload invoices have no XML)
- `GET /html` — returns 422 (no XML to render)

## Consequences

- Users can upload PDFs via `POST /api/invoices/upload` with multipart form data
- Partial extractions require a follow-up `PATCH /api/invoices/:id` to complete
- ML predictions only enqueue for complete extractions (partial ones may lack required fields)
- The invoices table grows with binary PDF data (~10MB max per invoice)
- The `@list_fields` exclusion pattern now covers both `xml_content` and `pdf_content`
