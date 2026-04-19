---
name: Per-User Public Invoice Tokens
description: Replace single per-invoice public token with per-(invoice, user) tokens stored as SHA-256 digests with 30-day TTL; token revocation on member block.
tags: [invoices, security, sharing, tokens]
author: emil
date: 2026-04-19
status: Accepted
---

# 0046. Per-User Public Invoice Tokens

Date: 2026-04-19

## Status

Accepted

## Context

Invoices sometimes need to be shared with external parties (e.g. a contractor querying payment status) via a public URL that requires no login. The original design stored a single `public_token` column directly on the `invoices` table. This had two problems:

1. **No attribution** — one token served all users; there was no way to know who generated a link or revoke a specific user's access without invalidating everyone's links.
2. **Plaintext storage** — bearer tokens stored as plaintext in the database are readable by anyone with DB access, creating unnecessary exposure.

## Decision

### Schema

Replace the single `invoices.public_token` column with a dedicated `invoice_public_tokens` table scoped to `(invoice_id, user_id)`:

```
invoice_public_tokens
  id          uuid PK
  invoice_id  uuid FK → invoices (on delete: cascade)
  user_id     uuid FK → users (on delete: cascade)
  token_digest string NOT NULL (SHA-256 hex, unique)
  expires_at  utc_datetime NOT NULL
  inserted_at utc_datetime NOT NULL
```

A unique constraint on `(invoice_id, user_id)` ensures at most one active token per user/invoice pair.

### Token security

Only the **SHA-256 digest** of the bearer token is persisted. The raw token is generated in memory, placed on the virtual `:token` field of the returned struct, and never written to the database. Lookups hash the incoming token before querying. This means:

- A DB breach exposes digests, not usable tokens.
- The raw token is shown exactly once (immediately after creation).
- Each "Copy public link" click rotates the token — the previous link is invalidated.

### TTL and rotation

Tokens expire **30 days** after creation. `ensure_public_token/2` always calls `rotate_public_token` (upsert with `on_conflict: {:replace, [:token_digest, :expires_at]}`), which:
1. Generates a new raw token.
2. Computes its digest.
3. Upserts the `(invoice_id, user_id)` row, replacing digest and expiry.
4. Reloads the struct from DB (for canonical ID), then sets the virtual `:token` field.

Concurrent callers converge on one row per `(invoice_id, user_id)` via the unique constraint.

### Revocation on member block

When a member is blocked, `Invoices.delete_public_tokens_for_user/2` deletes all tokens they created for that company's invoices. The block and deletion run inside a single `Repo.transaction` so neither can succeed without the other. An activity event (`member.public_tokens_revoked`) is emitted after the transaction.

## Consequences

- **Public URLs change** on every "Copy public link" click — previously valid links are invalidated when the user copies again. Acceptable because the user actively requested a new link.
- **No token recovery** — raw tokens cannot be recovered from the DB. This is intentional.
- **Audit trail** — token generation emits `invoice.public_link_generated`; bulk revocation emits `member.public_tokens_revoked`.
