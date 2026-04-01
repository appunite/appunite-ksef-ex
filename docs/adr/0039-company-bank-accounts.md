# 0039. Company Bank Accounts and Payment CSV Format

Date: 2026-04-01

## Status

Accepted

## Context

Payment request CSV export needs to produce files in a specific Polish bank transfer import format. This format requires:

1. **Orderer's bank account** (`rachunek_zleceniodawcy`) — the company's own IBAN for the transfer currency.
2. **Amount in cents** (`kwota`) — gross amount multiplied by 100, as an integer.
3. **Structured payment details** (`szczegóły_płatności`) — in `/NIP/<recipient_nip>/<transfer_title>` format.
4. **Split address** — street as `adres_1`, postal code + city as `adres_2`.

Previously the CSV used a generic 6-column format. The company schema had no bank account information, and payment requests had no recipient NIP field.

## Decision

### Company bank accounts as a separate table

Add a `company_bank_accounts` table with `company_id`, `currency` (3-letter ISO code), `iban`, and optional `label`. A unique constraint on `(company_id, currency)` enforces one account per currency per company.

**Why a separate table instead of a JSONB field on companies:**
- Normalized schema allows standard Ecto changesets with validation (IBAN length, currency format).
- Unique constraint is enforced at the database level.
- Easy to extend later (e.g., `is_default` flag if multiple accounts per currency become needed, or additional metadata like bank name).

### Recipient NIP on payment requests

Add a nullable `recipient_nip` string field to `payment_requests`. Pre-filled from `seller_nip` (expense) or `buyer_nip` (income) when creating from an invoice. Stored directly on the payment request so it works for standalone (no-invoice) payment requests too.

### New CSV format

The CSV builder now produces 7 columns:

```csv
kwota,nazwa_kontrahenta,rachunek_kontrahenta,rachunek_zleceniodawcy,szczegóły_płatności,adres_1,adres_2
```

The controller validates that all selected payment requests share the same currency and that a bank account exists for that currency before generating the CSV.

## Consequences

- Companies must configure a bank account for each currency before CSV export works. The controller returns a clear error if missing.
- Mixed-currency CSV exports are rejected — users must filter by currency first.
- The `recipient_nip` field is optional; when absent, `szczegóły_płatności` falls back to just the transfer title without the `/NIP/` prefix.
- Existing payment requests will have `recipient_nip` as `NULL` until re-created or manually updated.
