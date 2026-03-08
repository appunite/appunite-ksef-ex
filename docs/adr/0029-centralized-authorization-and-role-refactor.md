# 0029. Centralized Authorization and Role Refactor

Date: 2026-03-08

## Status

Accepted

## Context

Authorization logic was scattered across controllers, LiveViews, layouts, and contexts with inline role checks (`@current_role == :owner`, `role in [:owner, :accountant]`). This made it hard to reason about who can do what, and adding a new role required touching many files.

We needed to:
1. Add an `admin` role (same as owner except can't delete company or transfer ownership)
2. Tighten `reviewer` permissions (block categories/tags/exports/companies/certificates/team/tokens)
3. Redefine `accountant` as read-only for invoices with exports + API tokens access
4. Centralize authorization in one module

## Decision

Created `KsefHub.Authorization` as a pure-function module with a single `can?(role, permission)` function. All authorization checks throughout the codebase reference this module instead of doing inline role comparisons.

### Key components:
- **`lib/ksef_hub/authorization.ex`** — centralized permission matrix
- **`lib/ksef_hub_web/plugs/require_permission.ex`** — reusable API plug
- **LiveAuth hooks** — `:require_admin` for admin-only pages
- **Router restructure** — `:admin_only` live_session for certificates, categories, tags, team

### Role hierarchy:
- **Owner**: all permissions
- **Admin**: all except `delete_company` and `transfer_ownership`
- **Reviewer**: invoice CRUD, syncs (expense invoices only via existing query scoping)
- **Accountant**: read-only invoices, exports, API tokens

## Consequences

- Adding new permissions requires only updating `authorization.ex` and its tests
- New roles can be added by extending the `can?/2` function clauses
- Menu visibility, API authorization, and LiveView guards all use the same source of truth
- The `admin` role uses Ecto.Enum at the app level (string column), so no database migration was needed
