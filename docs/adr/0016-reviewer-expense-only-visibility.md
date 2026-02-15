# 0016. Restrict Reviewer Role to Expense Invoices Only

Date: 2026-02-15

## Status

Accepted

Refines the permission model in [ADR 0011](0011-per-company-rbac.md).

## Context

ADR 0011 introduced three roles (owner, accountant, reviewer) but gave all of them identical invoice visibility: every role can see both income and expense invoices. In practice, the reviewer role exists specifically for expense approval workflows — external bookkeepers or managers who should review and approve/reject expense invoices but have no business reason to access income invoice data (which contains sensitive revenue information, client details, and pricing).

The current implementation has no role-based invoice filtering. The `Invoices.list_invoices_paginated/2` context function and both the LiveView index and API index return all invoices for the company regardless of the caller's role. The `Companies.authorize/3` helper exists but is not used in any invoice code path.

## Decision

Restrict the `reviewer` role so it can only see expense invoices. Income invoices are invisible to reviewers across all access paths.

**Updated permission matrix (changes in bold):**

| Capability | `owner` | `accountant` | `reviewer` |
|---|---|---|---|
| View income invoices | yes | yes | **no** |
| View expense invoices | yes | yes | yes |
| Approve/reject expenses | yes | yes | yes |
| Download invoice PDF/XML | yes | yes | **expense only** |
| Manage certificates | yes | no | no |
| Manage API tokens | yes | no | no |
| Manage team | yes | no | no |

**Enforcement points:**

1. **Context layer (`KsefHub.Invoices`)** — `list_invoices_paginated/2` and `get_invoice/2` accept a `role` parameter. When role is `"reviewer"`, an automatic `type: "expense"` filter is applied. This is the single source of truth for the restriction.

2. **LiveView** — `InvoiceLive.Index` and `InvoiceLive.Show` pass `current_role` from socket assigns to context functions. Reviewers see the "Type" filter dropdown but only with the "expense" option (or the filter is hidden entirely). Attempting to navigate to an income invoice by ID returns "Invoice not found."

3. **API** — `Api.InvoiceController` resolves the role from the API token's company membership and passes it to context functions. Same filtering applies. The `type` query parameter is overridden/ignored for reviewers.

4. **Downloads** — `InvoicePdfController` (browser) and API download endpoints (`pdf`, `xml`, `html`) apply the same role-scoped lookup. A reviewer requesting a PDF/XML of an income invoice gets a 404.

**Why filter at the context layer, not the web layer:**

Filtering in the context ensures consistency across all access paths (LiveView, API, future CLI, background jobs). The web layer passes the role down; the context applies the constraint. This follows the existing pattern from ADR 0011: "Role is checked at the context layer, not just the web layer."

## Consequences

- Reviewers lose visibility into income invoices. This is intentional — if a user needs to see both, they should be assigned the accountant or owner role.
- The `type` filter in the UI/API becomes partially constrained for reviewers. The API should document this (OpenAPI spec update).
- Dashboard aggregate numbers (total invoices, revenue summaries) shown to reviewers should only reflect expense data, or the dashboard should be scoped accordingly.
- API tokens are company-scoped but not role-scoped today. The role must be resolved from the token owner's membership at request time, not cached on the token. This ensures role changes take effect immediately.
- Future role additions (e.g., `income_reviewer`) can reuse the same filtering mechanism by adding new role-to-type mappings in the context layer.
