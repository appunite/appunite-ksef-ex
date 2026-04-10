# 0043. Component-Driven UI

Date: 2026-04-11

## Status

Accepted

## Context

Across 20+ LiveView files, the same UI patterns were copy-pasted with minor variations: table wrappers (9 copies), empty state messages (5 copies), destructive button styling (6 copies), filter reset buttons (3 copies), and search inputs (2 copies). Changing any of these patterns required finding and updating every copy, making restyling, bug-fixing, and onboarding error-prone.

The project already had ~48 reusable components in CoreComponents, InvoiceComponents, CertificateComponents, and SettingsComponents, but several common layout and interaction patterns had not been extracted.

## Decision

1. **Extract shared UI patterns into CoreComponents** when they appear in 3+ places with near-identical structure. New components: `table_container`, `empty_state`, `search_input`, `reset_filters_button`, and the `outline-destructive` button variant.

2. **Placement rules:**
   - Domain-agnostic UI primitives (layout wrappers, form controls, display elements) go in `CoreComponents` (globally imported).
   - Domain-specific rendering (invoice badges, format helpers) stays in domain modules (e.g., `InvoiceComponents`).

3. **Extraction threshold:** a pattern must appear 3+ times with identical or near-identical structure before extracting. 2-occurrence patterns are noted but not extracted until a third appears.

4. **Component conventions:** every component must have `@doc`, `@spec`, and declarative `attr`/`slot` annotations. Support a `class` attr for caller customization when reasonable.

## Consequences

- **Smaller templates:** ~100 lines of duplicated HTML removed across LiveView files.
- **Single point of change:** styling or structural updates to tables, empty states, destructive buttons, etc. happen in one place.
- **Discoverability:** developers check CoreComponents before writing inline HTML.
- **Trade-off:** slight indirection — newcomers must know to look in CoreComponents for these patterns rather than seeing the raw HTML inline.
