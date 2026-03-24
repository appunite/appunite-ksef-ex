# 0035. Invoice Access Control

Date: 2026-03-24

## Status

Accepted

## Context

All invoices were visible to all company members (filtered only by role-based type scoping: reviewers saw only expenses). The team needs admins/owners to be able to restrict specific invoices so only selected reviewers can see them — for both sensitive expense invoices and income invoices.

Previously, income invoice visibility was enforced via hardcoded type scoping (`scope_by_role` forced `:type => :expense` for reviewers). This was rigid — there was no way to grant a specific reviewer access to a specific income invoice.

## Decision

Replace hardcoded type-based scoping with a unified access control system:

1. **`access_restricted` boolean on invoices** — when `true`, only explicitly granted users (plus admins/owners/accountants) can see the invoice.

2. **`invoice_access_grants` join table** — links users to invoices they're granted access to. Tracks `granted_by_id` for audit.

3. **Income invoices are always restricted** — `maybe_restrict_income/1` automatically sets `access_restricted: true` on income invoice creation/upsert. `set_access_restricted/2` rejects unrestricting income invoices.

4. **Single query filter** — `maybe_filter_by_access/3` applies a WHERE clause: `access_restricted = false OR id IN (SELECT invoice_id FROM grants WHERE user_id = ?)`. Roles with `:view_all_invoice_types` permission bypass this entirely.

5. **Permission model** — `:manage_team` permission (owner + admin) gates access grant management. Query filtering is automatic based on role — no explicit permission check needed.

### Visibility matrix

| Role       | Unrestricted expense | Restricted expense | Income (always restricted) |
|------------|---------------------|-------------------|---------------------------|
| Owner      | Yes                 | Yes               | Yes                       |
| Admin      | Yes                 | Yes               | Yes                       |
| Accountant | Yes                 | Yes               | Yes                       |
| Reviewer   | Yes                 | Only with grant   | Only with grant           |

### API endpoints

- `GET /api/invoices/:id/access` — view restriction status and grants
- `PUT /api/invoices/:id/access` — toggle restriction (blocked for income)
- `POST /api/invoices/:id/access/grants` — grant user access
- `DELETE /api/invoices/:id/access/grants/:user_id` — revoke access

## Consequences

- **Simpler model**: One mechanism (access grants) replaces two (type scoping + access grants). All invoice visibility decisions flow through `maybe_filter_by_access`.

- **Flexible income access**: Admins can now grant specific reviewers access to specific income invoices — previously impossible.

- **Migration required**: Existing income invoices get `access_restricted = true` via data migration. Existing expense invoices are unaffected (`access_restricted = false`).

- **Every invoice query path must pass `user_id`**: All callers (LiveView, API controllers, PDF controller) must thread `user_id` through opts. Missing `user_id` with a non-nil role means no access filtering occurs — this is safe because `full_invoice_visibility?(nil) = true` only applies when no role is set (internal/system calls).

- **No grant expiration**: Grants are permanent until explicitly revoked. This keeps the model simple but means admins must manually manage access.
