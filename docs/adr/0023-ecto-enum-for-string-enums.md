# 0023. Replace String Enums with Ecto.Enum

Date: 2026-02-24

## Status

Proposed

## Context

All enum-like fields across the codebase are stored as `:string` in Ecto schemas and validated with `validate_inclusion/3` against word lists (`@valid_types ~w(income expense)`, etc.). Business logic then compares these values with string equality checks:

```elixir
# Current: string comparisons everywhere
def approve_invoice(%Invoice{type: "expense", status: "pending"}) do
if socket.assigns[:current_role] == "owner" do
where(query, [i], i.type == "expense")
```

This has several problems:

- **No compile-time safety** — a typo like `"expens"` compiles fine and fails silently at runtime.
- **Not idiomatic Elixir** — atoms are the language's tool for named constants; strings are for user-facing text.
- **Verbose pattern matching** — `%Invoice{status: "pending"}` instead of `%Invoice{status: :pending}`.
- **No exhaustiveness hints** — Dialyzer cannot warn about unhandled enum values in string-based case/cond.

## Decision

Convert all string-based enum fields to `Ecto.Enum`. This stores strings in PostgreSQL (no migration needed) but presents atoms in Elixir code.

### Fields to convert

| Module | Field | Values |
|--------|-------|--------|
| `Invoice` | `type` | `:income`, `:expense` |
| `Invoice` | `status` | `:pending`, `:approved`, `:rejected` |
| `Invoice` | `source` | `:ksef`, `:manual`, `:pdf_upload` |
| `Invoice` | `extraction_status` | `:complete`, `:partial`, `:failed` |
| `Invoice` | `duplicate_status` | `:suspected`, `:confirmed`, `:dismissed` |
| `Invoice` | `prediction_status` | `:pending`, `:predicted`, `:needs_review`, `:manual` |
| `Checkpoint` | `checkpoint_type` | `:income`, `:expense` |
| `Membership` | `role` | `:owner`, `:accountant`, `:reviewer` |
| `Invitation` | `role` | `:accountant`, `:reviewer` |
| `Invitation` | `status` | `:pending`, `:accepted`, `:cancelled` |

### Schema change pattern

```elixir
# Before
field :type, :string
@valid_types ~w(income expense)
validate_inclusion(:type, @valid_types)

# After
field :type, Ecto.Enum, values: [:income, :expense]
# validate_inclusion is no longer needed — Ecto.Enum rejects invalid values at cast time
```

### Code change pattern

```elixir
# Before
def approve_invoice(%Invoice{type: "expense"} = invoice) do
where(query, [i], i.status == "pending")

# After
def approve_invoice(%Invoice{type: :expense} = invoice) do
where(query, [i], i.status == :pending)
```

### API layer

JSON serialization is unaffected. `Jason.encode/1` converts atoms to strings, so API responses remain `"status": "pending"`. Incoming JSON strings are cast to atoms by `Ecto.Enum` during changeset processing. OpenAPI schemas stay as `type: :string, enum: [...]`.

## Consequences

### Benefits

- Compile-time atom existence checks (misspelled atoms warn in some editors)
- Idiomatic Elixir — atoms for internal constants, strings for external boundaries
- Cleaner pattern matching: `%Invoice{status: :pending}` reads naturally
- `validate_inclusion` calls can be removed — `Ecto.Enum` enforces valid values at cast time
- Dialyzer can reason about atom values better than arbitrary strings

### Trade-offs

- Large cross-cutting diff (~10 fields, ~150+ string comparison sites across lib/, test/, templates)
- Every test that inserts or asserts enum values must change from `"pending"` to `:pending`
- Factory defaults change from `status: "pending"` to `status: :pending`
- LiveView templates change from `@type == "income"` to `@type == :income`
- Ecto query filters from API params need explicit cast (string params to atoms) — but `Ecto.Enum` handles this via changesets

### Recommendation

Do this as a standalone refactor after the pdf_upload feature is merged. Tackle in priority order:

1. `Invoice.type` and `Invoice.status` (highest usage, ~53 sites)
2. `Membership.role` (~22 sites, affects auth layer)
3. `Invoice.source` (~12 sites)
4. Remaining fields (lower usage, straightforward)

Each field can be a separate commit — no database migration required since PostgreSQL column type stays `text`.
