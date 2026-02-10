# 0014. Company Invitation System

Date: 2026-02-10

## Status

Accepted

## Context

With open sign-up ([ADR 0013](0013-email-password-auth.md)) and per-company RBAC ([ADR 0011](0011-per-company-rbac.md)), there needs to be a controlled way for company owners to grant access to their company. A user cannot simply create a duplicate company for the same NIP (NIP has a unique constraint), so they must be invited by the owner to gain access to an existing company.

## Decision

Introduce an `invitations` table:

```
invitations
├── id
├── company_id      (FK → companies)
├── email           (invitee email address)
├── role            (enum: accountant | invoice_reviewer)
├── invited_by_id   (FK → users, the owner who created the invitation)
├── token_hash      (SHA-256 of the invitation token)
├── status          (enum: pending | accepted | cancelled)
├── expires_at      (7 days from creation)
└── inserted_at
```

**Invitation flow:**

1. Company owner creates an invitation with an email and role (owner role cannot be invited — only the creator is owner).
2. System generates a secure token (same pattern as API tokens: 32 bytes, SHA-256 hashed in DB) and sends an email with a tokenized accept link.
3. **If the invitee has an account:** They click the link, verify the token, and a `membership` is created with the specified role.
4. **If the invitee does not have an account:** They click the link, are redirected to sign up, and the pending invitation is auto-accepted on first login (matched by email).
5. Invitations expire after 7 days. Expired invitations cannot be accepted.
6. Owner can cancel pending invitations from the team management UI.

**Validation rules:**

- Cannot invite an email that already has a membership for the same company — return a clear error.
- Cannot invite to the `owner` role — ownership is assigned only at company creation.
- One pending invitation per email per company (unique constraint on `company_id` + `email` where status = `pending`).

## Consequences

- Email delivery is required (same Swoosh dependency as [ADR 0013](0013-email-password-auth.md) for confirmation/reset emails).
- Invitation tokens are hashed in the database, following the same security pattern as API tokens ([ADR 0006](0006-api-token-hashed-bearer.md)).
- The team management page (owner-only) becomes the central place for managing access: view members, send invitations, cancel pending invitations, remove members.
- Edge case handling needed: invitation to an email that already has a membership, expired token clicks, re-inviting after cancellation.
