# 0032. Expense Categories & Typed Tags

Date: 2026-03-14

## Status

Accepted

## Context

Categories and tags were previously untyped and shared across expense and income invoices. In practice, categories only make sense for expenses — the ML classifier only runs on expense invoices, and there is no income classification model yet. Tags need separate subsets per invoice type to avoid confusion between expense and income tag sets.

## Decision

- **Restrict categories to expense invoices only** — rename to "Expense Categories" throughout the UI and API. `set_invoice_category` rejects income invoices with `{:error, :expense_only}`.
- **Add `type` enum (`:expense`/`:income`) to tags** with default `:expense`. The unique constraint becomes `[company_id, name, type]`, allowing the same tag name to exist independently for expense and income.
- **Settings UI** uses Expense/Income tabs on the Tags page (via `?type=` query param). The Categories page is renamed to "Expense Categories" with no tabs needed.
- **Invoice show page** hides the category section for income invoices and filters available tags by the invoice's type.
- **Invoice list page** filters the tag dropdown by the active invoice type tab. Category filter only shows for expense view.
- **API**: `GET /api/tags` accepts optional `?type=` query param. `POST /api/tags` accepts `type` in body (defaults to `"expense"`). Tag JSON responses include the `type` field.
- **Classifier** explicitly filters `find_tag_by_name` by `type: :expense`.

## Consequences

- All existing tags are migrated as expense (the column defaults to `"expense"`).
- Same tag name can exist independently for expense and income namespaces.
- Category assignment is rejected for income invoices (API returns 422).
- Future income classifier can use income-typed tags directly without schema changes.
- The unique constraint change means duplicate tag names within the same company are allowed if they have different types.
