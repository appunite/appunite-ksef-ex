# 0044. Correction Invoice Support

Date: 2026-04-15

## Status

Accepted

## Context

KSeF issues correction invoices (faktura korygująca) as separate documents with their own KSeF numbers. The FA(3) XML standard distinguishes invoice kinds via the `RodzajFaktury` element: `VAT` (standard), `KOR` (correction), `ZAL` (advance), `ROZ` (advance settlement), `UPR` (simplified), `KOR_ZAL` (advance correction), `KOR_ROZ` (settlement correction).

Correction invoices carry additional metadata referencing the original:

- `NrFaKorygowanej` — business number of the corrected invoice
- `NrKSeFFaKorygowanej` — KSeF number of the corrected invoice
- `DataFaKorygowanej` — issue date of the corrected invoice
- `OkresFaKorygowanej` — period range being corrected
- `PrzyczynaKorekty` — reason for correction
- `TypKorekty` — when the correction takes effect (1=original date, 2=correction date, 3=other)

Prior to this change, the system had no concept of invoice kinds. All invoices — standard, corrections, advances — were stored identically with no way to distinguish or link them. Correction invoices appeared as regular invoices with no indication of what they corrected.

### Key design questions

1. **Naming**: FA(3) codes like `KOR`, `KOR_ZAL` are Polish abbreviations meaningless to API consumers and non-Polish developers. Should the data model use Polish codes or English names?

2. **Linking**: Should corrections be linked to originals via a foreign key, or only store the reference string?

3. **Sync ordering**: Corrections may arrive before their originals during sync. How to handle this?

## Decision

### English enum values with FA(3) mapping

The `invoice_kind` Ecto.Enum uses descriptive English atoms:

| FA(3) code | Ecto enum / DB / API |
|------------|---------------------|
| `VAT` | `vat` |
| `KOR` | `correction` |
| `ZAL` | `advance` |
| `ROZ` | `advance_settlement` |
| `UPR` | `simplified` |
| `KOR_ZAL` | `advance_correction` |
| `KOR_ROZ` | `settlement_correction` |

The mapping from FA(3) codes to English identifiers lives in a single place: `Parser.@fa3_kind_mapping`. English labels are used in `Invoice.invoice_kind_label/1` for UI display, consistent with the rest of the English-language UI.

**Why not use FA(3) codes directly**: The API serves external consumers who shouldn't need to know Polish tax abbreviations. `"correction"` is self-documenting; `"KOR"` is not. Internal consistency also benefits — the existing `type` field uses English (`:income`, `:expense`), not Polish.

### FK linking + string reference

Each correction invoice stores both:

- `corrected_invoice_ksef_number` (string) — the raw KSeF reference, always preserved even if the original invoice isn't in our system
- `corrects_invoice_id` (FK to `invoices`) — resolved at sync time by looking up the original by `ksef_number` within the same company

This mirrors the existing `duplicate_of_id` pattern. The FK enables bidirectional queries (find corrections for an invoice, find the original of a correction). The string ensures data integrity when the original hasn't been synced yet.

### Two-phase FK resolution for sync ordering

1. **Inline**: During sync, `InvoiceFetcher.maybe_link_corrected_invoice/2` looks up the original immediately. If found, sets the FK.
2. **Post-sync backfill**: After both income and expense syncs complete, `Invoices.link_unlinked_corrections/1` runs a bulk SQL update matching unlinked corrections to originals by `ksef_number`. This handles corrections that arrived before their originals.

The backfill uses raw SQL for bulk performance and bypasses the ActivityLog system intentionally — linking is a bookkeeping step, not a user-visible mutation.

### Correction kind helpers

`Invoice.correction_kinds/0` returns `[:correction, :advance_correction, :settlement_correction]` as the single source of truth. `Invoice.correction?/1` delegates to it. Filter queries and UI components reference this function rather than hardcoding the list.

## Consequences

### Schema

New fields on `invoices` table:

| Column | Type | Notes |
|--------|------|-------|
| `invoice_kind` | string (Ecto.Enum) | Default `"vat"`, not null |
| `corrected_invoice_number` | string | Nullable |
| `corrected_invoice_ksef_number` | string | Nullable |
| `corrected_invoice_date` | date | Nullable |
| `correction_period_from` | date | Nullable |
| `correction_period_to` | date | Nullable |
| `correction_reason` | string | Nullable, max 1000 chars |
| `correction_type` | integer | Nullable, values 1/2/3 |
| `corrects_invoice_id` | FK to invoices | Nullable, nilify on delete |

Indexes: `corrects_invoice_id`, `(company_id, invoice_kind)`.

### API

- `invoice_kind` field exposed on all invoice responses with English values
- `invoice_kind` and `is_correction` query parameters on the list endpoint
- CSV export includes Invoice Kind, Corrected Invoice Number, Corrected KSeF Number, Correction Reason columns

### UI

- **Kind badge**: Red "Correction" badge for correction invoices in list and detail views. No badge for standard VAT (default).
- **Correction details panel**: "Correction invoice" panel on correction invoice detail pages with original reference (linked if FK resolved), reason, effect type, and period.
- **Related invoices table**: Shows on both original and correction invoice detail pages, linking in both directions.

### Trade-offs

- The `correction_details` guard in `invoice_components.ex` must hardcode the correction kind atoms because Elixir guards require compile-time values. A comment marks this as needing sync with `Invoice.correction_kinds/0`.
- `link_unlinked_corrections/1` bypasses ActivityLog — no `invoice.correction_linked` events are emitted for bulk FK resolution. Individual FK sets during sync do emit events via the normal changeset path.
- No manual linking UI exists. Corrections created via PDF upload or email cannot be linked to originals through the UI. This is acceptable because correction→original linking is primarily a KSeF concern.
