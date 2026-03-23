# 0034. Invoice Exclusion

Date: 2026-03-23

## Status

Accepted

## Context

Users need a way to exclude specific invoices from reports and aggregations without deleting them or changing their approval status. Common reasons include: invoices that should not appear in expense summaries (e.g. internal transfers, test invoices, or one-off corrections), while still keeping them visible in the system for audit purposes.

Deletion is not appropriate because the invoice may have come from KSeF sync and must be retained. Rejection changes the approval workflow status, which has different semantics — a rejected invoice means "we will not pay this", not "ignore this for reporting".

## Decision

Add an `is_excluded` boolean field to the invoices table (default `false`, not null):

- **Schema** — `field :is_excluded, :boolean, default: false` on the `Invoice` schema, included in the general changeset cast list.
- **Context functions** — `exclude_invoice/1` and `include_invoice/1` wrap `update_invoice/2` with the appropriate flag value.
- **UI** — exposed via an "Actions" dropdown menu on the invoice detail page header, alongside the existing Share action. Shows "Exclude" when included and "Include" when excluded. An "excluded" badge appears in the subtitle area when the flag is set.
- **Authorization** — guarded by the existing `can_mutate` permission (same as edit, share, and other mutation actions).
- **Button reordering** — as part of this change, the header actions were reordered to: Approve, Reject, Download, Actions. This puts the most frequent approval workflow actions on the left for prominence, and groups secondary actions (Share, Exclude/Include) in the dropdown.

## Consequences

- Additive schema change — no impact on existing invoices (all default to `is_excluded: false`).
- **Exports** — excluded invoices are filtered out of export batches (`exportable_invoices_query` includes `is_excluded == false`). They will not appear in CSV summaries or ZIP downloads.
- Aggregation queries and list filters do not yet exclude these invoices — that filtering can be added incrementally as reporting features are built out.
- The exclusion flag is independent of status, type, and source — any invoice can be excluded regardless of its other attributes.
- Future work may include filtering excluded invoices from dashboard charts.
