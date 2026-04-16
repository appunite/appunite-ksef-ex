# Architecture Decision Records (ADRs)

ADRs document significant technical decisions — what was decided, why, and what trade-offs were accepted. They are the primary mechanism for capturing architectural intent that cannot be inferred from reading the code.

---

## When to Write an ADR

Write an ADR when:

- Choosing between two or more viable technical approaches
- Establishing a pattern that other developers will be expected to follow (e.g. how to handle X, where Y lives)
- Making a decision with non-obvious trade-offs
- Superseding a previous decision

Do **not** write an ADR for:
- Obvious implementation choices with no meaningful alternatives
- Bug fixes or routine feature work that follows existing patterns
- Changes that are fully explained by a PR description

**Rule of thumb:** if a new developer would wonder "why did they do it this way?", write an ADR.

---

## Naming Convention

```text
docs/adr/NNNN-short-title.md
```

Use the next sequential number. Titles should be lowercase, hyphen-separated, concise:
- `0045-invoice-export-format.md`
- `0046-rate-limit-strategy.md`

---

## Format

```markdown
---
name: Short Title
description: One-line summary of the decision
tags: [tag1, tag2]
author: your-name
date: YYYY-MM-DD
status: Accepted
---

# NNNN. Short Title

Date: YYYY-MM-DD

## Status
Accepted | Superseded by NNNN

## Context
Why this decision was needed. What problem it solves. What constraints existed.

## Decision
What was decided. Be specific — this should read as a clear statement of what to do.

## Consequences
Trade-offs accepted. Known downsides. What becomes easier or harder as a result.
```

**Frontmatter vs body — which is canonical:**

Both `status` and `date` appear twice: once in the YAML frontmatter and once in the body (`## Status` section and the `Date:` line under the title). The **frontmatter fields are canonical** — they are the machine-readable source of truth used by tooling (e.g., `/update-architecture` when building the ADR index). The body fields are human-readable mirrors and must be kept in sync with the frontmatter.

- Both locations are **required**. An ADR missing either the frontmatter field or its body counterpart is incomplete.
- Valid values for `status` are `Accepted`, `Superseded by NNNN` (replace NNNN with the superseding ADR number), and `Implemented` (for decisions fully baked into the codebase with no ongoing guidance needed).
- The `date` field records when the decision was made, not when the file was last edited.

---

## After Writing an ADR

1. Run `/update-architecture` to add the new ADR to the index in `docs/architecture.md`
2. Reference the ADR in relevant code comments or module docs where appropriate

---

## Superseding an ADR

When a later decision overrides an earlier one:

1. In the **old** ADR, update both the canonical frontmatter (`status: Superseded by NNNN`) and its body mirror (`## Status` → `Superseded by NNNN`). Both must be changed together — tooling reads the frontmatter; humans read the body.
2. Do **not** change the decision date. Both the frontmatter `date` and its body mirror (`Date: YYYY-MM-DD` under the title) must remain the original decision date — even when amending or superseding. Only correct the date if it was recorded incorrectly in the first place.
3. Reference the old ADR in the new ADR's `## Context` section.
4. Run `/update-architecture` to update both rows in the ADR index.
