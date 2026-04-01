# 0038. Project Tag

Date: 2026-04-01

## Status

Accepted

## Context

The business needs to attribute invoices to specific projects or teams for expense allocation and project tracking. The old system had `expenseProposedProjectTag` — a free-form string on expense invoices only. The new system extends this to both income and expense invoices, enabling correlation of project costs and revenue.

This is distinct from the existing tag system (multi-label entities with a join table) and cost lines (fixed enum of business cost centers). Project tag is a single free-form string per invoice — lightweight and user-driven.

## Decision

Add a `project_tag` nullable string field directly on the invoices table.

- **Both invoice types** — works on income and expense invoices, unlike categories and cost lines which are expense-only.
- **Free-form string** — no predefined values. Max length 255 characters. No separate entity or join table.
- **Dynamic suggestions** — `list_project_tags/1` queries distinct `project_tag` values from invoices created in the last year, ordered by most recently used. The available tag list grows organically as users create new values.
- **Single-select** — one project tag per invoice (radio buttons in UI), not multi-label like the tag system.
- **UI** — section in the classify page with radio buttons for existing tags, custom input for new values. Displayed as a green badge inline with regular tags on show and list pages.
- **API** — `PUT /api/invoices/:id/project-tag` to set/clear, `GET /api/project-tags` to list available values.
- **Permissions** — reuses `:set_invoice_tags` permission rather than introducing a new one.

## Consequences

- No migration needed when users create new project tags — values are stored directly on the invoice.
- The one-year window on `list_project_tags` keeps the suggestion list relevant without manual cleanup.
- Tag matching is case-sensitive (for example, "Alpha" and "alpha" are treated as different tags); this can be changed to use citext if needed.
- Sharing the `:set_invoice_tags` permission means project tag and tag permissions cannot be controlled independently. Acceptable for now given they serve similar classification purposes.
