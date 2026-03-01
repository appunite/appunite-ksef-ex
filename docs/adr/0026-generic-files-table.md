# 0026. Generic Files Table for Binary Content

Date: 2026-03-01

## Status

Implemented (supersedes ADR 0021)

## Context

The invoices table stores `xml_content` (text) and `pdf_content` (binary) directly in the row. Both columns are excluded from list queries via `@list_fields` to avoid loading large blobs. The `inbound_emails` table also stores `pdf_content` for temporary staging during email processing.

ADR 0021 proposed an `invoice_documents` table with an `invoice_id` FK (child → parent), designed to support "multiple documents per invoice." However, this flexibility is unnecessary in the KSeF domain:

- A **correction** (`faktura korygująca`) is a separate KSeF document with its own `ksef_number` — it becomes a new invoice record, not an additional attachment on the original.
- Each invoice has **at most** one XML (KSeF source) and one PDF (uploaded or generated) — never multiple of the same type.

A simpler approach: a generic files table where **the parent holds a FK to the file**, not the other way around.

## Decision

Create a generic `files` table for all binary content storage:

```sql
CREATE TABLE files (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content bytea NOT NULL,
  content_type text NOT NULL,  -- "application/xml", "application/pdf", etc.
  filename text,
  byte_size integer,
  inserted_at timestamptz NOT NULL DEFAULT now()
);
```

Reference files via explicit FK columns on the owning tables:

```sql
-- On invoices
ALTER TABLE invoices ADD COLUMN pdf_file_id uuid REFERENCES files(id);
ALTER TABLE invoices ADD COLUMN xml_file_id uuid REFERENCES files(id);

-- On inbound_emails
ALTER TABLE inbound_emails ADD COLUMN pdf_file_id uuid REFERENCES files(id);
```

Then migrate existing data and drop the inline content columns (`invoices.xml_content`, `invoices.pdf_content`, `inbound_emails.pdf_content`).

## Consequences

### Benefits
- **Leaner tables** — list queries are naturally fast without field exclusions, `@list_fields` workaround can be removed
- **Reusable** — any table can reference `files` (invoices, inbound_emails, future tables)
- **Explicit semantics** — `pdf_file_id` and `xml_file_id` make the relationship and type obvious, no need for JOINs with WHERE clauses to find "the PDF"
- **Simple queries** — `Repo.preload(:pdf_file)` or a direct JOIN by ID
- **One file, one purpose** — matches the domain reality (one XML, one PDF per invoice)

### Trade-offs
- Requires data migration for existing content columns
- All code reading `invoice.xml_content` / `invoice.pdf_content` must change to `invoice.pdf_file` / `invoice.xml_file`
- Orphaned files need cleanup (files not referenced by any FK) — a periodic Oban job or ON DELETE handling
- Adding a new document type per invoice means adding a new FK column (but this is rare and explicit)

### Migration strategy

1. Create `files` table
2. Add `pdf_file_id` / `xml_file_id` FK columns (nullable) to `invoices` and `pdf_file_id` to `inbound_emails`
3. Migrate existing content into `files`, set FKs
4. Update application code to read/write via file associations
5. Drop old content columns

### Implementation note

Implemented in the `feat/generic-files-table` branch as a standalone refactor after the inbound email feature was stable.
