---
name: Rename Expense-Specific Invoice Columns
description: Prefix all expense-only invoice schema columns with `expense_` / `prediction_expense_` to make their domain semantics explicit in schema, API, and DB.
tags: [invoices, api, schema, database]
author: emil
date: 2026-04-16
status: Accepted
---

# 0045. Rename Expense-Specific Invoice Columns

Date: 2026-04-16

## Status

Accepted

## Context

The `invoices` table stores both income and expense invoices in a single unified schema (ADR-0007). Several columns exist solely for expense invoices yet had generic names that gave no indication of their scope:

| Old column | Scope |
|------------|-------|
| `status` | Expense-only (approval workflow) |
| `category_id` | Expense-only (ML classification) |
| `cost_line` | Expense-only (cost center attribution) |
| `prediction_category_name/confidence/model_version/probabilities` | Expense-only (ML output) |
| `prediction_tag_name/confidence/model_version/probabilities` | Expense-only (ML output) |

This naming created two recurring problems:

1. **Ambiguity in code** — `invoice.status` looks like it applies to all invoices. Developers regularly needed to check the schema or behavioural contracts to confirm income invoices always have `status: :pending` and that the field carries no meaning for them. The same confusion applied to `category_id` and `cost_line`.

2. **Ambiguity in the API** — External consumers of the REST API saw a `"status"` field in both income and expense invoice responses with no indication that it is only meaningful for expenses. The OpenAPI schema carried a comment, but the field name itself was misleading.

The existing `tags` column was intentionally excluded from this rename because it applies to both invoice types (ADR-0040).

## Decision

Rename all 11 expense-specific invoice columns by prefixing them with `expense_` or updating the `prediction_` prefix to `prediction_expense_`:

| Old name | New name |
|----------|----------|
| `status` | `expense_approval_status` |
| `category_id` | `expense_category_id` |
| `cost_line` | `expense_cost_line` |
| `prediction_category_name` | `prediction_expense_category_name` |
| `prediction_category_confidence` | `prediction_expense_category_confidence` |
| `prediction_category_model_version` | `prediction_expense_category_model_version` |
| `prediction_category_probabilities` | `prediction_expense_category_probabilities` |
| `prediction_tag_name` | `prediction_expense_tag_name` |
| `prediction_tag_confidence` | `prediction_expense_tag_confidence` |
| `prediction_tag_model_version` | `prediction_expense_tag_model_version` |
| `prediction_tag_probabilities` | `prediction_expense_tag_probabilities` |

The rename propagates through:
- DB schema (migration using `rename table(:invoices), :old, to: :new`)
- Ecto schema and all changeset/cast lists
- All context modules, queries, analytics, classification, and export logic
- REST API request parameters and JSON response fields
- OpenAPI schema definitions
- LiveView socket assigns and form input names

**What was intentionally NOT renamed:**

- `export_batches.category_id` — a separate table column recording which category filter was used when creating an export batch; it is not an invoice field
- `tags` — applies to both invoice types
- Activity log event type strings (`"invoice.status_changed"`, `"invoice.classification_changed"`) — semantic event identifiers, not field references
- The metadata key `"field" => "cost_line"` in historical activity log records — old records are left as-is; new events emit `"expense_cost_line"`. The activity log display code matches both values for backward compatibility.

## Consequences

### Breaking API change

All 11 field names change in both JSON responses and accepted request parameters. Any external consumer of the REST API must update their integration. There is no deprecation period or backward-compatible aliasing — the old names are gone.

### Clarity gains

Field semantics are now self-documenting. A developer reading `invoice.expense_approval_status` immediately knows the field only applies to expenses, without consulting behavioural contracts or ADR-0007. The same applies to `expense_category_id` and `expense_cost_line`.

### Activity log backward compatibility

Historical activity log records stored with `"field" => "cost_line"` remain in the database unchanged. The settings LiveView activity log display matches on both `"cost_line"` and `"expense_cost_line"` with an explicit comment explaining the compatibility shim.

### Schema FK derivation

Ecto derives the FK column name for `belongs_to`/`has_many` associations from the association name by convention. After renaming `category_id` to `expense_category_id`, the `Category` schema's `has_many :invoices` association required an explicit `foreign_key: :expense_category_id` option — Ecto can no longer derive it from the association name alone.
