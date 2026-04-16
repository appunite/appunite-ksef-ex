# KSeF Integration Guide

KSeF (Krajowy System e-Faktur) is Poland's national e-invoice system operated by the Ministry of Finance. All VAT-registered companies in Poland must issue and receive invoices through it.

---

## Authentication Flow

KSeF uses XADES-signed challenge authentication:

1. `getChallenge(nip)` — request a challenge token for the company's NIP
2. Sign the challenge XML with the company's PKCS12 certificate (via `xmlsec1`)
3. `authenticate(signed_challenge)` — returns a raw token
4. `redeemToken(raw_token)` — returns a session token (1-hour TTL)
5. Use session token for all subsequent API calls
6. `terminateSession()` — always call when done

See `docs/ksef-certificates.md` for certificate types and how to generate them.

---

## Session Management

- Sessions expire after **1 hour** — do not let them expire passively
- Always call `terminateSession` when done, even on error paths
- If a session expires mid-sync, re-authenticate and continue from the last checkpoint
- Only one active session is allowed per NIP — starting a new session invalidates any previous session for that NIP

---

## Rate Limits

| Operation | Limit | Implementation |
|-----------|-------|----------------|
| Invoice download | 8 req/s | `Process.sleep(125)` between requests |
| Query | 2 req/s | `Process.sleep(500)` between queries |

Exceeding limits results in `429` responses. The sync worker respects these with inline sleeps.

---

## Invoice Sync Flow

Sync runs via Oban cron (default every 60 min, configurable via `SYNC_INTERVAL_MINUTES`):

1. Load company certificate → authenticate → get session
2. Query invoice headers (incremental — since last checkpoint per invoice type)
3. Download each XML (rate-limited at 8 req/s)
4. Parse FA(3) XML → upsert to DB
5. Advance checkpoint
6. Terminate session

Key files: `lib/ksef_hub/sync/`, `lib/ksef_hub/ksef_client/`

---

## FA(3) XML Format

Invoices are delivered as FA(3) XML — a Ministry of Finance format with Polish field codes. The parser (`lib/ksef_hub/invoices/parser.ex`) extracts all structured data from the XML and stores it in the `invoices` table.

For the full field mapping, XML structure, correction invoice fields, and parsing edge cases, see `docs/fa3-xml.md`.

---

## Re-parsing Stored XML

When the FA(3) parser is improved (new fields extracted, bug fixes), existing invoices can be re-parsed from their stored XML **without a full KSeF re-sync**. This is done via a Cloud Run Job:

```bash
gcloud run jobs execute ksef-hub-migrate \
  --region europe-west1 \
  --wait \
  --args 'eval,KsefHub.Release.reparse_ksef_invoices(dry_run: true)'
```

Remove `dry_run: true` to apply changes. See `docs/operations.md` for the full operations guide.

The re-extraction module (`lib/ksef_hub/invoices/reextraction.ex`) also handles re-extracting data from stored PDFs via the invoice-extractor sidecar when the extractor is updated.

---

## Useful Links

| Resource | URL |
|----------|-----|
| KSeF Test Environment | https://ksef-test.mf.gov.pl |
| KSeF Production | https://ksef.mf.gov.pl |
| FA(3) Schema (XSD) | http://crd.gov.pl/wzor/2025/06/25/13775/schemat.xsd |
| FA(3) Stylesheet (XSL) | http://crd.gov.pl/wzor/2025/06/25/13775/styl.xsl |
