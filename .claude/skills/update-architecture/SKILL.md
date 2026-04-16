---
name: update-architecture
description: This skill should be used when the user asks to "update architecture.md", "update the architecture guide", "update the ADR index", "sync architecture docs", or after writing a new ADR, adding a new feature area or context module, discovering a non-obvious behavioral invariant, or renaming/moving key files.
---

# Update Architecture Guide

Sync `docs/architecture.md` to reflect recent changes to the codebase. The file has three sections — only update the sections affected by what changed.

## Sections and their update triggers

### Feature → Files Map

Update when:
- A new context module is added (e.g., `lib/ksef_hub/payments.ex`)
- A new LiveView section is added
- A new background job type is introduced
- Key files for an existing feature are renamed or moved

When adding a row: identify the feature name and its key files (facade + relevant sub-modules + web layer entry point). Keep the "Key files" cell to 2–4 paths — not exhaustive, just the files a developer would open first.

### Behavioral Contracts

Update when:
- A non-obvious invariant is introduced or enforced in code
- An existing invariant changes or is removed

What qualifies as a behavioral contract:
- Not derivable from reading a single function — spans multiple features or files
- Getting it wrong would cause a bug, not just confusion
- Examples: status rules (`income invoices always stay :pending`), type restrictions (`categories are expense-only`), immutability constraints, access scoping

Format: one row per invariant — `| Invariant description | Source ADR or file |`

Do NOT add contracts for obvious things that a developer would infer immediately from reading one function.

### ADR Index

Update when:
- A new ADR is written in `docs/adr/`
- An existing ADR is superseded

When adding a row: read the ADR file, then extract: filename (without `docs/adr/` prefix), title, status, and a one-line decision summary — what was decided, not why (the "why" is in the ADR itself).

When marking superseded: update the Status cell on the old ADR row to `Superseded by NNNN`, and add the new ADR row.

## Workflow

**Step 1 — Identify what changed.**

Check what files were touched since branching from main:

```bash
git diff main --name-only
```

Also list ADR files to spot any new ones:

```bash
ls docs/adr/
```

**Step 2 — Read `docs/architecture.md`** to understand current state before editing.

**Step 3 — Determine which sections need updating** based on what changed:
- New `docs/adr/NNNN-*.md` file → ADR Index
- New `lib/ksef_hub/<context>/` or `live/<page>_live*` → Feature → Files Map
- Invariant enforced in code that isn't in Behavioral Contracts → Behavioral Contracts
- Superseded ADR (another ADR's status says "Supersedes...") → update old row

**Step 4 — Read any new ADR files** to extract accurate summaries before editing the index.

**Step 5 — Make targeted edits.** Only modify the rows/sections that need updating. Do not reformat or reorder unrelated content.

**Step 6 — Verify** that superseded ADRs have both their old row updated AND the new row added.

## What NOT to change

- Internal implementation details (private functions, helpers) do not belong in Feature Map
- Behavioral contracts for things obvious from one function
- Sections unaffected by the current changes
- The structure, heading order, or formatting of unchanged rows
