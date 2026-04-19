---
name: Approver and Analyst Roles (rename reviewer/viewer)
description: Rename :reviewer → :approver and :viewer → :analyst to clarify role intent; analyst has identical data scope to approver (access grants apply).
tags: [authorization, roles, team]
author: emil
date: 2026-04-19
status: Accepted
---

# 0047. Approver and Analyst Roles

Date: 2026-04-19

## Status

Accepted

## Context

The system previously had `:reviewer` and `:viewer` roles. Both names implied passive, read-only behavior, making it hard to distinguish them at a glance:

- `:reviewer` is the **primary operational role** — the person who approves/rejects expense invoices, manages categories, triggers KSeF syncs, and handles payment requests. "Reviewer" undersells this.
- `:viewer` is a **read-only analytics consumer** — someone who needs to look up invoice details (e.g. to reconcile data exported to another system). "Viewer" is too close to "reviewer" and doesn't communicate purpose.

## Decision

Rename:

| Old | New | Rationale |
|-----|-----|-----------|
| `:reviewer` | `:approver` | Action-oriented — this role approves/rejects invoices |
| `:viewer` | `:analyst` | Persona-oriented — this role consumes data for analysis |

### Permissions (unchanged from previous `:viewer`)

`:analyst` retains the same data scope as `:approver`: both see non-restricted invoices by default and receive access via per-invoice grants for restricted ones. `:analyst` has no management permissions.

```elixir
@analyst_permissions MapSet.new([:view_invoices])
```

This means `:analyst` is **not** equivalent to `:accountant` (which has `:view_all_invoice_types` and bypasses the access-grant filter). If an analyst needs to see a restricted invoice, an owner/admin grants them access explicitly — the same mechanism used for approvers.

### Route gating

`/invoices/:id/classify` was moved from the unprotected `:authenticated` live_session to a new `:require_set_category` session that requires `:set_invoice_category`. `/settings` was moved to `:require_view_dashboard`. Both are now unreachable to `:analyst` (and any other role without the relevant permission).

### Invitation roles

`:analyst` is **not** an invitable role — the invitation flow offers `admin`, `accountant`, `approver` only. An analyst can only be assigned via the team member edit page.

## Migration

A single migration updates the `memberships.role` and `invitations.role` string columns:

```sql
UPDATE memberships SET role = 'approver' WHERE role = 'reviewer';
UPDATE memberships SET role = 'analyst'  WHERE role = 'viewer';
UPDATE invitations SET role = 'approver' WHERE role = 'reviewer';
```

## Consequences

- Existing `:reviewer` members become `:approver` with identical permissions — no functional change.
- Existing `:viewer` members become `:analyst` with identical permissions — no functional change.
- All code references (atoms, strings, UI labels, test fixtures) updated in the same commit.
- `role_label/1` derives from `Atom.to_string/1` + `String.capitalize/1`, so the UI automatically shows "Approver" and "Analyst".
