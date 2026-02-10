# 0006. Hashed Bearer API Tokens

Date: 2026-02-07

## Status

Accepted — auth context updated by [ADR 0011](0011-per-company-rbac.md) (per-company RBAC) and [ADR 0013](0013-email-password-auth.md) (email/password auth replaces Google Sign-In + allowlist)

## Context

KSeF Hub serves two audiences from a single deployment:

1. **Admin UI** — authenticated via Google Sign-In with an email allowlist (`ALLOWED_EMAILS`), protected by session cookies
2. **Consumer applications** — external systems (ERP, accounting software) that need programmatic access to invoices, PDFs, and approval workflows via REST API

Consumer applications cannot use Google Sign-In. They need long-lived, revocable API tokens with minimal overhead per request. The token system must be secure against database breaches — if the database is compromised, stolen token data should not grant API access.

## Decision

We implement **hashed bearer tokens** following the pattern used by GitHub, Stripe, and similar platforms:

### Token Lifecycle

1. **Generation**: 32 bytes (256 bits) of cryptographically secure randomness via `:crypto.strong_rand_bytes/1`, Base64url-encoded (no padding). Produced in `KsefHub.Accounts.create_api_token/1`.
2. **Hashing**: SHA-256 hash stored in `token_hash` column. The plaintext token is returned to the user exactly once on creation and never stored.
3. **Prefix**: First 8 characters stored in `token_prefix` for identification in the admin UI (e.g., "Which token is this?") without exposing the full value.
4. **Validation**: On each API request, `KsefHub.Accounts.validate_api_token/1` hashes the incoming bearer token and looks up the hash with `is_active: true`.
5. **Revocation**: Soft-delete via `is_active: false`. Revoked tokens fail validation immediately.
6. **Usage tracking**: `last_used_at` timestamp and `request_count` integer updated on each successful authentication via `Accounts.track_token_usage/1`.

### Request Flow

The `KsefHubWeb.Plugs.ApiAuth` plug extracts `Bearer <token>` from the `Authorization` header, validates via hash lookup, tracks usage, and assigns the token to `conn.assigns.api_token`. Failed auth returns 401 with `halt()`.

### API Routes

All routes under `/api` pass through the `:api_auth` pipeline:

- `GET /api/invoices` — list with filters (type, status, NIP, date range, text search)
- `GET /api/invoices/:id` — single invoice
- `POST /api/invoices/:id/approve` — approve expense invoice
- `POST /api/invoices/:id/reject` — reject expense invoice
- `GET /api/invoices/:id/pdf` — generate and download PDF
- `GET /api/tokens` — list tokens (for admin)
- `POST /api/tokens` — create new token (returns plaintext once)
- `DELETE /api/tokens/:id` — revoke token

### Token Management

Token CRUD is exposed via `KsefHubWeb.Api.TokenController` behind the same bearer auth. This means existing token holders can create and revoke tokens — initial token provisioning happens through the LiveView admin UI (Google Sign-In auth).

Alternatives considered:

- **JWT tokens**: Stateless validation but no revocation without a blocklist. Token rotation is complex. Overkill for a single-service API.
- **OAuth2 client credentials**: Standard protocol but adds authorization server complexity for a system with a single API surface.
- **API keys in query parameters**: Visible in server logs and browser history. Bearer header is the standard approach.
- **HMAC request signing**: Stronger replay protection but significantly more complex for consumers to implement. Not warranted for the current threat model.

## Consequences

- **Database lookup per request**: Every API call requires a hash lookup + usage update. The unique index on `token_hash` keeps this fast. Could add caching (ETS) later if latency becomes an issue.
- **Breach-resistant**: A database dump exposes only SHA-256 hashes, which cannot be reversed to valid tokens.
- **One-time plaintext display**: If a user loses their token, they must revoke and create a new one. No recovery mechanism by design.
- **No token expiration**: Tokens are valid until revoked. Could add optional TTL later if needed.
- **Usage visibility**: `last_used_at` and `request_count` help identify unused tokens for cleanup and detect suspicious activity patterns.
