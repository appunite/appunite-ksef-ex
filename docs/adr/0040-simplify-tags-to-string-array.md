# 0040. Simplify Tags from Entity to String Array

Date: 2026-04-01

## Status

Accepted. Supersedes the original tag entity design.

## Context

Tags were implemented as a full entity system: a `tags` table (id, name, description, type, company_id), a `invoice_tags` join table, CRUD API endpoints, and a settings UI for managing tags. This worked but created a sync problem with the ML classification pipeline.

The ML classifier (au-payroll-model-categories sidecar) predicts tag names as strings. The old system required those strings to match pre-existing `Tag` records in the database — if the model learned a new tag name, the prediction would silently fail to match unless someone manually created a matching tag in the settings UI first. This coupling between the ML pipeline and the app's tag registry was the core problem.

In practice:
- Most tags were assigned by the ML model, not created manually.
- Tag names should not be edited in the app (they come from the model's vocabulary).
- The tag settings UI and CRUD API added complexity for a workflow that shouldn't exist.
- The `project_tag` field (ADR 0038) already proved the free-form string approach works well.

## Decision

Replace the tag entity system with a `tags` string array column directly on the `invoices` table.

### What changed

- **Schema**: `many_to_many :tags` through join table → `field :tags, {:array, :string}`, default `[]`.
- **Storage**: Two tables (`tags`, `invoice_tags`) → one column with a GIN index.
- **ML classifier**: No more `find_tag_by_name` lookup against the `tags` table. Predicted tag strings are stored directly on the invoice. Any string above the confidence threshold is applied — no matching step.
- **API**: Tag CRUD endpoints (`POST/PUT/DELETE /api/tags`) removed. `PUT /api/invoices/:id/tags` now accepts `{tags: ["string", ...]}` instead of `{tag_ids: [uuid, ...]}`. `GET /api/tags` returns distinct tag strings instead of tag objects.
- **UI**: Settings tag management page removed. Classify page uses string checkboxes instead of entity-backed checkboxes. Creating a tag inline adds a string to the local list (persisted on save), not a database record.
- **Permissions**: `:manage_tags` permission removed (no tag CRUD to protect). `:set_invoice_tags` still governs who can assign tags to invoices.
- **Validation**: Max 50 tags per invoice, max 100 characters per tag. Tags are trimmed, deduplicated, and blank strings rejected on write.

### Data migration

A single migration adds the `tags` column, copies existing tag names from the join table via `array_agg`, then drops both `invoice_tags` and `tags` tables. Tag names are preserved; tag IDs and descriptions are not (descriptions were rarely used).

### Querying

- Filter by tag: `WHERE tags && ARRAY['tag_name']` (PostgreSQL array overlap, uses GIN index).
- List distinct tags: `SELECT DISTINCT unnest(tags) FROM invoices WHERE company_id = ?`.

## Consequences

- **ML pipeline decoupled**: The classifier stores predicted strings directly. No sync between model vocabulary and app database.
- **~600 lines removed**: Tag schema, join schema, CRUD context functions, controller, settings LiveView, OpenAPI schemas, tests.
- **~60 lines added**: Three context functions (`set_invoice_tags`, `add_invoice_tag`, `list_distinct_tags`), changeset with validation, two OpenAPI schemas.
- **Breaking API change**: Consumers using `tag_ids` (UUIDs) must switch to `tags` (strings). The `GET /api/tags` response changes from tag objects to a string list.
- **Human-created tag drift**: Users can create tags inline on the classify page (free-form text input). This means typos and case variations (e.g., "Rent" vs "rent" vs "RENT") will produce distinct tags — there is no uniqueness enforcement. This is a first-class behavioral outcome, not a theoretical risk. It affects tag filtering, reporting aggregations, and any downstream system that groups by tag name. The same pattern is already proven acceptable with `project_tag` (ADR 0038), which has worked well without normalization. If drift becomes problematic, normalize to lowercase on write.
- **No tag descriptions**: The old `Tag.description` field is gone. It was rarely used and not surfaced in the ML pipeline.
- **Performance**: `unnest` + `GROUP BY` for `list_distinct_tags` scans invoices in the company. Adequate for current scale; can add a materialized view if needed later.
