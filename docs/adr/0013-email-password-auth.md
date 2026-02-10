# 0013. Email/Password Authentication

Date: 2026-02-10

## Status

Accepted

Supersedes the authentication model in [ADR 0006](0006-api-token-hashed-bearer.md) and [ADR 0008](0008-multi-company-support.md) (Google Sign-In + `ALLOWED_EMAILS`).

## Context

The app was gated by Google Sign-In combined with an `ALLOWED_EMAILS` environment variable, limiting access to a pre-approved set of internal users. This was appropriate for an internal tool but blocks the shift to self-service SaaS where any accountant or business owner should be able to sign up.

ADR 0006 references "Google Sign-In with an email allowlist" as the UI auth mechanism. ADR 0008 states "the email allowlist is the sole access gate." Both assumptions are replaced by this decision.

## Decision

Implement email/password authentication using `phx.gen.auth` (or equivalent Elixir auth scaffolding):

**Core features:**

- `users` table with `email`, `hashed_password`, `confirmed_at`
- Email confirmation required before full access
- Password reset via tokenized email link
- Session-based authentication for LiveView (session token in cookie)

**Google Sign-In:** Kept as an optional, additional login method. When a user authenticates via Google, the system matches by email to an existing account (or creates one with `confirmed_at` set, since Google has already verified the email). This provides convenience without being a requirement.

**Removed:** The `ALLOWED_EMAILS` environment variable is removed entirely. Access control is now handled by the membership system ([ADR 0011](0011-per-company-rbac.md)), not by an env-based allowlist.

**API auth unchanged:** Bearer API tokens ([ADR 0006](0006-api-token-hashed-bearer.md)) remain the authentication mechanism for REST API consumers. API tokens are now scoped to a company and created by company owners.

## Consequences

- Any user can sign up — the barrier to entry is email confirmation, not admin approval.
- The `users` table gains `hashed_password` and `confirmed_at` columns (previously users were identified only by Google email).
- Email delivery becomes a dependency for confirmation and password reset (Swoosh with SMTP/Mailgun adapter).
- Google Sign-In becomes a convenience path, not the only path — users without Google accounts can participate.
- No more env-based access control — deployment no longer needs `ALLOWED_EMAILS` to be maintained.
