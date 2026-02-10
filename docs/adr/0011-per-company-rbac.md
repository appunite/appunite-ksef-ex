# 0011. Per-Company Role-Based Access Control

Date: 2026-02-10

## Status

Accepted

Supersedes the flat access model in [ADR 0008](0008-multi-company-support.md).

## Context

ADR 0008 introduced multi-company support but kept a flat access model: all authenticated users see all companies, with the email allowlist (`ALLOWED_EMAILS`) as the sole access gate. This worked for an internal tool with a known set of users, but the shift to a self-service SaaS model requires per-company access control so that company owners control who sees their data.

## Decision

Introduce a `memberships` join table linking users to companies with a role:

```
memberships
├── user_id     (FK → users)
├── company_id  (FK → companies)
├── role        (enum: owner | accountant | invoice_reviewer)
└── inserted_at
```

**Roles and permissions:**

| Capability | `owner` | `accountant` | `invoice_reviewer` |
|---|---|---|---|
| View invoices | yes | yes | yes |
| Approve/reject expenses | yes | yes | yes |
| Manage certificates | yes | no | no |
| Manage API tokens | yes | no | no |
| Manage team (invite/remove) | yes | no | no |
| Company settings | yes | no | no |

**Enforcement points:**

- Every context function that touches company-scoped data checks the caller's membership and role.
- LiveView `on_mount` hooks verify membership for the current company and assign the role to the socket.
- API controllers verify that the API token belongs to a company where the authenticated user has an appropriate role.
- UI conditionally renders tabs, buttons, and pages based on the assigned role.

**Company creation:** When a user creates a company, an `owner` membership is automatically created in the same transaction.

## Consequences

- Every company-scoped query gains a membership check, adding a join but ensuring data isolation.
- The `ALLOWED_EMAILS` env var is no longer the access gate — membership replaces it (see [ADR 0013](0013-email-password-auth.md)).
- Role is checked at the context layer, not just the web layer, so API and LiveView share the same authorization logic.
- Future roles can be added to the enum without schema changes to the membership table.
