# 0021. Future Invoice Documents Table

Date: 2026-02-24

## Status

Proposed

## Context

The invoices table now stores both `xml_content` (text, for KSeF invoices) and `pdf_content` (binary, for uploaded PDFs) directly in the row. Both columns are excluded from list queries via `@list_fields` to avoid loading large blobs into memory.

This exclusion pattern is a code smell — large binary data shouldn't live in the main query table. As more document types are added (e.g., scanned images, corrected PDFs), this pattern doesn't scale.

## Decision

Extract binary content into a dedicated `invoice_documents` table:

```sql
CREATE TABLE invoice_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  content_type text NOT NULL,  -- "application/xml", "application/pdf", etc.
  content bytea NOT NULL,
  filename text,
  inserted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_invoice_documents_invoice_id ON invoice_documents(invoice_id);
```

Migrate existing `xml_content` and `pdf_content` into this table, then remove both columns from invoices.

## Consequences

### Benefits
- Leaner invoices table — list queries are naturally fast without field exclusions
- Unified document storage — all document types handled the same way
- Support for multiple documents per invoice (e.g., original + corrected)
- Cleaner API — `GET /invoices/:id/documents` to list, `GET /invoices/:id/documents/:doc_id` to download

### Trade-offs
- Requires data migration for existing invoices
- Additional JOINs when loading document content
- All code reading `invoice.xml_content` or `invoice.pdf_content` must change
- PDF generation flow changes from `invoice.xml_content` to document lookup

### Recommendation

Do this as a standalone refactor after the pdf_upload feature is stable, not as part of the initial implementation. Wait for at least one production cycle to validate the pdf_upload flow before restructuring storage.
