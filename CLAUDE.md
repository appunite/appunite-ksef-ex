# KSeF Hub

Multi-tenant service for Poland's KSeF (National e-Invoice System). Owns certificate authentication, XADES signing, FA(3) XML parsing, incremental invoice sync, PDF generation, and ML-based categorisation for multiple companies — exposing clean REST APIs and a LiveView admin UI.

Two invoice types drive most of the domain logic: **income** (issued by the company, synced read-only from KSeF, no approval workflow) and **expense** (received invoices, arriving via KSeF sync, PDF upload, or inbound email, with approval workflow and ML auto-classification).

Before making changes, read @docs/architecture.md. It contains:
- **Feature → Files Map** — which files to look at for each feature area
- **Behavioral Contracts** — non-obvious invariants that affect multiple features
- **ADR Index** — one-line summaries of every architecture decision

For any non-trivial task, scan the ADR index first and read only the ADRs whose summaries match your task. This is faster than exploring the codebase blind.

After writing a new ADR, adding a feature area, or discovering a non-obvious invariant, run `/update-architecture` to keep `@docs/architecture.md` in sync.

For tech stack, project structure, setup commands, Make targets, and environment variables, see @README.md.

## Architecture

### Contexts

Phoenix contexts are the primary boundaries. Each context owns its schema, queries, and business logic.

| Context | Responsibility |
|---------|---------------|
| `KsefHub.Invoices` | CRUD, filtering, approval/rejection of invoices |
| `KsefHub.Credentials` | Certificate upload, encryption, expiry tracking |
| `KsefHub.KsefClient` | All KSeF API communication (auth, query, download) |
| `KsefHub.PdfRenderer` | PDF and HTML generation via pdf-renderer sidecar |
| `KsefHub.InvoiceExtractor` | PDF → structured JSON extraction via invoice-extractor sidecar |
| `KsefHub.InvoiceClassifier` | ML-based category/tag classification via invoice-classifier service |
| `KsefHub.Accounts` | API token generation, validation, usage tracking |

### Module Size & Modularization

Context modules must stay maintainable. When a context file grows beyond **~500 lines**, proactively extract cohesive function groups into sub-modules under the context namespace.

**Pattern:** The context module stays as a **thin public API facade** using `defdelegate` or one-line wrappers. Sub-modules hold the implementation. Callers always use `Context.function()` — never call sub-modules directly from controllers or LiveViews.

```elixir
# In lib/ksef_hub/invoices.ex (facade)
defdelegate confirm_duplicate(invoice, opts), to: Invoices.Duplicates
defdelegate list_invoice_comments(company_id, invoice_id), to: Invoices.Comments

# Callers unchanged:
Invoices.confirm_duplicate(invoice, opts)
```

**When to extract:**
- A cluster of 5+ functions shares a single responsibility (e.g., all filtering, all comment CRUD)
- Private helpers only serve that cluster
- The cluster can be moved without circular dependencies back to the facade

**Current sub-modules (Invoices):** `Extraction`, `Analytics`, `Comments`, `AccessControl`, `Classification`, `Queries`, `Reextraction`, `Duplicates`

**Current sub-modules (Accounts):** `ApiTokens`

### Activity Log (Trackable + TrackedRepo)

Every context mutation that affects user-visible state **must** emit an activity event. Schemas implement the `Trackable` behaviour; context functions use `TrackedRepo` instead of `Repo` — event emission is automatic, no manual event names needed.

**When to use `Events.*` directly** (no changeset available):
- Login/logout (session management)
- Sync triggers (Oban job, no schema mutation)
- Multi transactions (insert after `Repo.transaction`)
- Cross-entity events (invoice comments need invoice's company_id)

**Actor context:** LiveView handlers pass `actor_opts(socket)` → `[user_id: ..., actor_label: ...]`. System operations pass `actor_type: "system", actor_label: "KSeF Sync"`.

Key files:
- `lib/ksef_hub/activity_log/trackable.ex` — behaviour that schemas implement
- `lib/ksef_hub/activity_log/tracked_repo.ex` — Repo wrapper with auto event emission + no-op detection
- `lib/ksef_hub/activity_log/events.ex` — `emit/1` dispatch + manual helpers for non-changeset events
- `lib/ksef_hub/activity_log/recorder.ex` — GenServer that persists events to DB

For implementation pattern, Trackable code examples, and the full list of schemas/events, see `@docs/adr/0042-activity-log.md`.

### Dependency Injection with Behaviours

External services are accessed through behaviours so tests can use mocks (via Mox):

```elixir
# Define behaviour
defmodule KsefHub.KsefClient.Behaviour do
  @callback authenticate(credentials :: map()) :: {:ok, session} | {:error, term()}
  @callback fetch_invoices(session, params) :: {:ok, [invoice]} | {:error, term()}
end

# Production implementation
defmodule KsefHub.KsefClient.Live do
  @behaviour KsefHub.KsefClient.Behaviour
  # ... actual HTTP calls to KSeF API
end

# In config/test.exs
config :ksef_hub, :ksef_client, KsefHub.KsefClient.Mock

# In test_helper.exs
Mox.defmock(KsefHub.KsefClient.Mock, for: KsefHub.KsefClient.Behaviour)
```

Access the configured implementation via application env:

```elixir
defp ksef_client, do: Application.get_env(:ksef_hub, :ksef_client, KsefHub.KsefClient.Live)
```

### Key flows

**KSeF Authentication:** getChallenge(nip) -> sign with XADES (xmlsec1 + PKCS12 cert) -> authenticate(signed challenge) -> redeemToken -> session (1h TTL) -> terminateSession on completion.

**Invoice Sync (every 60 min):** Load certificate -> authenticate -> query invoice headers (incremental, since last sync) -> download each XML (rate-limited) -> parse FA(3) -> upsert to DB -> update last_sync_at -> terminate session.

**PDF Generation:** FA(3) XML -> pdf-renderer sidecar -> PDF.

**PDF Extraction:** Uploaded PDF (non-KSeF invoice) -> invoice-extractor sidecar -> structured JSON.

**Invoice Classification (Oban, on expense creation):** New expense invoice -> ClassifierWorker -> invoice-classifier service -> auto-assign category/tags.

For sidecar service integration details (endpoints, auth, request/response formats), see @docs/sidecar-services.md.

## Code Style

### Idiomatic Elixir

- Use `|>` pipelines for data transformation chains
- Use `with` for multi-step operations that can fail
- Use pattern matching in function heads over conditionals
- Use guards to constrain function clauses
- Small, focused functions (< 15 lines ideally)
- Descriptive function and variable names

```elixir
# Good: pipeline with clear intent
def process_invoice(xml) do
  xml
  |> parse_fa3()
  |> validate_required_fields()
  |> build_changeset()
  |> Repo.insert()
end

# Good: with for fallible steps
def sync_invoices(credentials) do
  with {:ok, session} <- authenticate(credentials),
       {:ok, headers} <- fetch_invoice_headers(session),
       {:ok, count} <- download_and_store(session, headers) do
    terminate_session(session)
    {:ok, count}
  end
end

# Good: pattern matching in function heads
def handle_response({:ok, %{status: 200, body: body}}), do: {:ok, body}
def handle_response({:ok, %{status: 401}}), do: {:error, :unauthorized}
def handle_response({:error, reason}), do: {:error, {:request_failed, reason}}
```

### Naming conventions

- Modules: `PascalCase` (`KsefHub.Invoices.Parser`)
- Functions/variables: `snake_case` (`fetch_invoice_headers`)
- Boolean functions: end with `?` (`expired?/1`); reserve `is_` prefix for guard-safe predicates (`is_nil/1`, `is_binary/1`)
- Private functions: prefix with `do_` only when wrapping a public function (`defp do_parse/1`)
- Test files: mirror source path (`test/ksef_hub/invoices_test.exs`)

### Documentation & Typespecs

Every module **must** have:

- `@moduledoc` — describes the module's purpose
- `@type t :: %__MODULE__{}` — on all Ecto schemas
- `@doc` — on every public function
- `@spec` — on every function (public and private)

### SOLID / DRY

- Single responsibility modules — one context per domain concept
- Extract shared logic into dedicated modules, don't copy-paste
- Depend on behaviours, not concrete implementations
- Keep web layer thin — controllers delegate to contexts

## UI Components

Before writing inline HTML in a LiveView template, check `CoreComponents` first. Domain-specific components live in `InvoiceComponents`, `CertificateComponents`, and `SettingsComponents`. Extract shared patterns when they appear 3+ times. For the full component reference, color tokens, and DaisyUI usage, use the `/frontend` skill.

## Testing

We follow TDD (red-green-refactor). Tests use ExUnit with `async: true`, ExMachina for test data factories, and Mox for mocking external services. For test structure, factory patterns, Mox setup, and fixture conventions, see `@docs/tests.md`.

## Project Conventions

### OpenAPI Documentation (required for every API endpoint)

Every REST API controller action **must** have an `open_api_spex` operation spec — this is NOT automatic. For the annotation template, schema conventions, and checklist, see `@docs/openapi.md`.

### ADR (Architecture Decision Records)

Every significant technical decision gets an ADR in `docs/adr/`. After implementing a feature, consider whether the decisions made warrant one. For format, naming convention, and when to create, see `@docs/adr.md`.

### Commits

- Use conventional commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`
- Keep commits focused — one logical change per commit
- Write the "why" in the commit body when not obvious

### Branches & PRs

- Feature branches off `main`
- PR title matches the primary commit convention
- PRs should include tests for new behaviour

## Security

### Certificate handling

- PKCS12 certificates encrypted at rest with AES-256-GCM
- Certificate password encrypted separately (AES-256-GCM)
- Encryption key: base64-decoded `CREDENTIAL_ENCRYPTION_KEY` (32 bytes), falls back to `SHA256(SECRET_KEY_BASE)`
- Audit log on every certificate operation (upload, decrypt, use for signing)

For KSeF certificate types, how to generate them, and portal usage, see @docs/ksef-certificates.md.

### Temp file security (xmlsec1 interaction)

When calling xmlsec1 for XADES signing:

1. Write cert/password to temp files with `0600` permissions
2. Never pass passwords as CLI arguments (visible in `ps`)
3. After use: overwrite temp files with zeros, then delete
4. Apply 30-second timeout on System.cmd calls

```elixir
# Pattern for secure temp file usage
{:ok, path} = Temp.write(content, mode: 0o600)
try do
  System.cmd("xmlsec1", [..., path], timeout: 30_000)
after
  secure_delete(path)
end
```

### API tokens

- Store only hashed tokens in the database (never plaintext)
- Show full token to user exactly once on creation
- Track `last_used_at` and request count per token
- Support revocation

### General

- Never log certificates, passwords, or token values
- Sanitize filenames in `Content-Disposition` headers (prevent header injection)
- Use Ecto transactions + unique constraints for atomicity

## KSeF Domain Specifics

KSeF (Krajowy System e-Faktur) is Poland's national e-invoice system. Invoices are synced via an authenticated XADES API session, parsed from FA(3) XML format, and stored in the database. When parser logic improves, existing invoices can be re-parsed from stored XML without a full re-sync.

For authentication flow, rate limits, session rules, re-parsing, and FA(3) details, see `@docs/ksef.md`.
