# 0025. Inbound Email Invoice Processing

Date: 2026-02-25

## Status

Accepted

## Context

Accountants often work from their email inbox. Sending expense invoices via email reduces friction — no need to log in to the UI or use the API. We need a way for each company to receive PDF expense invoices via a unique email address, process them through the existing extraction pipeline, verify they belong to the correct company, and reply with status.

Key requirements:
- **Expenses only** — buyer NIP must match the company NIP
- **Single PDF attachment per email** — reject zero, multiple, or non-PDF
- **Sender domain restriction** — only accept emails from a configured domain
- **Async processing** — webhook returns immediately, Oban worker handles extraction

## Decision

Use **Mailgun inbound routes** (webhook-based, no SMTP server) to receive emails:

1. **Per-company email addresses** via random 8-char alphanumeric tokens: `inv-{token}@inbound.ksef-hub.com`. Tokens are opt-in (null until enabled), regenerable if compromised.

2. **Single catch-all Mailgun route** `match_recipient(".*@inbound.ksef-hub.com")` forwards to `POST /webhooks/mailgun/inbound`. No per-company route management.

3. **Webhook controller** verifies HMAC-SHA256 signature, validates sender domain, parses company token, validates exactly one PDF attachment, stores to `inbound_emails` table, and enqueues Oban worker.

4. **Async Oban worker** (`InboundEmailWorker`) loads the PDF from `inbound_emails.pdf_content`, calls the unstructured extraction service, verifies NIP ownership via `NipVerifier`, creates invoice via `create_email_invoice/4`, and sends reply email.

5. **NIP verification** enforces expense-only:
   - buyer NIP matches → accept as expense
   - seller NIP matches → reject (income invoice)
   - neither matches → reject (wrong company)
   - NIPs not extracted → accept but flag "needs review"

6. **Reply emails** sent to both the original sender and a CC address (`INBOUND_CC_EMAIL` env var).

7. **PDF storage**: Binary stored in `inbound_emails.pdf_content` during processing, then copied to `invoice.pdf_content` (matching existing pdf_upload flow).

## Consequences

### Positive
- ~70% of backend logic reused from existing pdf_upload flow
- No SMTP server to manage — Mailgun handles email reception
- Async processing with retry via Oban
- Audit trail via `inbound_emails` table with idempotency on `mailgun_message_id`
- Sender domain restriction prevents spam without complex authentication

### Negative
- Adds Mailgun as infrastructure dependency
- Requires DNS MX record setup for inbound subdomain
- Company email tokens must be managed (enable/disable/regenerate)
- Sender domain restriction limits who can submit invoices

### Note on ADR 0021 (future `invoice_documents` table)
Current implementation stores PDF binary in `inbound_emails.pdf_content` (temporary, during processing) and then in `invoice.pdf_content` (permanent, matching existing pdf_upload flow). When ADR 0021's `invoice_documents` table is implemented:
1. `inbound_emails.pdf_content` can remain as-is (temporary staging area)
2. The worker should insert into `invoice_documents` instead of setting `invoice.pdf_content`
3. The `inbound_emails.pdf_content` column can optionally be dropped

### Environment variables (new)

| Variable | Description |
|----------|-------------|
| `MAILGUN_SIGNING_KEY` | Webhook signing key from Mailgun dashboard |
| `INBOUND_EMAIL_DOMAIN` | Domain for inbound email addresses |
| `INBOUND_ALLOWED_SENDER_DOMAIN` | Only accept emails from this domain |
| `INBOUND_CC_EMAIL` | CC address for all reply notifications |
