---
name: review
description: Critical review of recent changes for code quality, test coverage, DRY/SOLID, documentation, and architecture. Use after completing a feature.
disable-model-invocation: true
effort: max
---

Perform a thorough critical review of the changes made in this conversation. Be a strict reviewer — flag real problems, not nitpicks.

## Review checklist

### 1. Feature correctness
Step back and evaluate whether the feature was implemented properly:
- Does the implementation actually solve the stated problem?
- Are there edge cases or failure modes that were missed?
- Could a simpler approach achieve the same result?

### 2. Code quality & maintainability
- Are functions focused and small (< 15 lines)?
- Are module boundaries clean — does each module have a single responsibility?
- Is error handling consistent and complete?
- Are there any code smells (long parameter lists, deep nesting, boolean parameters)?

### 3. DRY / SOLID principles
- Is there duplicated logic that should be extracted into a shared module?
- Are there opportunities to introduce abstractions that would make code reusable elsewhere?
- Do modules depend on abstractions (behaviours) rather than concrete implementations where appropriate?
- Is there dead code that should be removed?

### 4. Test coverage
- Are all new public context functions covered by unit tests?
- Are LiveView interactions tested (mount, events, navigation)?
- Are edge cases tested (not found, unauthorized, invalid input)?
- Are error paths tested, not just happy paths?
- Do tests verify side effects (e.g., blocked user actually loses access)?

### 5. Documentation
- Do all new public functions have `@doc` and `@spec`?
- Are `@moduledoc` descriptions up to date with the changes?
- Are non-obvious design decisions documented?

### 6. Architecture decisions
- If this change introduces a significant pattern, convention, or architectural decision, propose an ADR (Architecture Decision Record) in `docs/adr/` following the project convention.

## Output format

1. List issues found, grouped by category, with severity: **critical** / **should fix** / **nice to have**
2. For each issue, explain WHY it matters and suggest a concrete fix
3. After listing issues, fix all **critical** and **should fix** items
4. Run `mix format`, `mix credo --strict`, and `mix test` at the end to verify everything passes
