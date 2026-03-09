# 0030. Public Shareable Invoice URLs

Date: 2026-03-08

## Status

Accepted

## Context

Users needed a way to share individual invoices with people who don't have accounts in the system — external accountants, vendors, company members without login, or as links in email replies. Previously, viewing any invoice required authentication and company membership.

We considered several approaches:

1. **Signed URLs with expiry** — JWT or HMAC-signed URLs that expire after N hours. Pros: self-contained, no DB column. Cons: links break after expiry (bad for email threads), requires secret rotation strategy, URL length.
2. **Separate share_links table** — a dedicated table with token, invoice_id, created_by, expires_at, revoked_at. Pros: full audit trail, revocable, supports expiry. Cons: extra table, extra join, over-engineered for current needs.
3. **Per-invoice token column (chosen)** — a nullable `public_token` on the invoices table, generated lazily on first share. Pros: simple, fast lookup (indexed), no joins, idempotent. Cons: no per-share audit trail, no built-in expiry.

## Decision

Added a `public_token` column to the `invoices` table — a base64url-encoded 32-byte random value, generated on-demand when a user first clicks "Share" on an invoice. The token is nullable (most invoices will never be shared) with a partial unique index on non-NULL values.

### URL scheme

```text
/public/invoices/:id?token=<base64url_token>
```

The URL requires both the invoice UUID and the token. Knowing just the invoice ID is not enough — the token acts as the authorization secret.

### Key design decisions

**Lazy generation, not on creation.** Tokens are generated only when `ensure_public_token/1` is called (triggered by the Share button). This avoids bloating the table with tokens for invoices that are never shared.

**No expiry.** Shared links are permanent. This fits the primary use case (email threads, Slack messages) where links should remain valid indefinitely. If expiry is needed later, we can add an `expires_at` column without changing the URL scheme.

**Logged-in member redirect.** If a user with company membership opens a public link, they're redirected to the authenticated detail page (`/c/:company_id/invoices/:id`). This prevents confusion from having two views of the same invoice.

**Read-only public view.** The public page shows invoice details and preview only — no approve/reject, notes, comments, categories, tags, or edit controls. This is enforced at the template level (separate LiveView, not conditional rendering in the existing Show).

**Separate LiveView, not a mode flag.** `PublicShow` is a distinct LiveView from `Show`. This avoids accidentally leaking authenticated UI through missed conditionals, and keeps each LiveView focused (single responsibility).

**Shared components.** The read-only details table (`invoice_details_table`) and preview generation (`generate_preview`) are extracted into `InvoiceComponents` and reused by both Show and PublicShow.

### Race condition handling

Two concurrent "Share" clicks could both see `public_token: nil` and attempt to generate. The unique constraint on `public_token` prevents duplicate tokens. `ensure_public_token/1` detects the constraint error and reloads the invoice to return the winning token.

## Consequences

**Positive:**
- Simple implementation — one column, one index, three context functions
- Links are stable (no expiry to manage or broken-link complaints)
- Public view is isolated from authenticated view (no leaking of controls)
- Token is cryptographically strong (256-bit random), not guessable from invoice ID

**Negative:**
- No revocation mechanism — if a link leaks, it can't be individually revoked (would need to NULL the token and regenerate, losing the old link)
- No audit trail of who shared or when (the token is generated but not attributed)
- No rate limiting on public view (could be added at the CDN/proxy layer if needed)

**Future considerations:**
- Add `public_token_generated_at` and `public_token_generated_by_id` if audit trail becomes important
- Add expiry support via `public_token_expires_at` column if needed
- Add a "Revoke" button that NULLs the token (next share generates a new one)
- Consider adding the share_links table if per-link tracking, multiple links per invoice, or fine-grained permissions are needed
