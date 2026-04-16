# KSeF Hub

Dedicated service for Poland's National e-Invoice System (KSeF). Owns all KSeF complexity — certificate authentication, XADES signing, FA(3) XML parsing, invoice sync, PDF generation — and exposes clean REST APIs for any consumer application.

See `docs/prd.md` for full product requirements.

Before making changes, read `docs/architecture.md`. It contains:
- **Feature → Files Map** — which files to look at for each feature area
- **Behavioral Contracts** — non-obvious invariants that affect multiple features
- **ADR Index** — one-line summaries of every architecture decision

For any non-trivial task, scan the ADR index first and read only the ADRs whose summaries match your task. This is faster than exploring the codebase blind.

After writing a new ADR, adding a feature area, or discovering a non-obvious invariant, run `/update-architecture` to keep `docs/architecture.md` in sync.

For tech stack, project structure, setup commands, Make targets, and environment variables, see `README.md`.

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

Every context mutation that affects user-visible state **must** emit an activity event. Schemas implement the `Trackable` behaviour to classify their own changesets into events. Context functions use `TrackedRepo` instead of `Repo` — no manual event names needed.

```elixir
# 1. Schema implements Trackable (defines what events its changes produce):
@behaviour KsefHub.ActivityLog.Trackable

@impl true
def track_change(%Ecto.Changeset{action: :insert} = cs) do
  {"invoice.created", %{source: to_string(get_field(cs, :source))}}
end

def track_change(%Ecto.Changeset{} = cs) do
  case cs.changes do
    %{status: new} -> {"invoice.status_changed", %{old: to_string(cs.data.status), new: to_string(new)}}
    %{is_excluded: true} -> {"invoice.excluded", %{}}
    _ -> {"invoice.updated", %{changed_fields: Map.keys(cs.changes)}}
  end
end

# 2. Context function is 2-3 lines (TrackedRepo handles the rest):
def approve_invoice(%Invoice{} = invoice, opts \\ []) do
  invoice
  |> Invoice.changeset(%{status: :approved})
  |> TrackedRepo.update(opts)
end
```

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
- `docs/adr/0042-activity-log.md` — architecture decision record

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

### Component-first development

Before writing inline HTML in a LiveView template, check `CoreComponents` for an existing component. Common components:

| Category | Components |
|----------|-----------|
| Layout | `card`, `table`, `table_container`, `header` |
| Forms | `input`, `simple_form`, `multi_select`, `date_range_picker`, `date_picker`, `search_input` |
| Display | `badge`, `icon`, `pagination`, `empty_state` |
| Filters | `multi_select`, `date_range_picker`, `search_input`, `reset_filters_button` |
| Actions | `button` (variants: primary, outline, outline-destructive, ghost, destructive, success, warning) |

Domain-specific components live in dedicated modules:
- `InvoiceComponents` — status/type/category/payment badges, format helpers, invoice detail table
- `CertificateComponents` — certificate expiry alerts
- `SettingsComponents` — settings page sidebar layout

### When to extract a component

- **3+ identical occurrences** of the same HTML across views → extract to `CoreComponents`
- **Domain-agnostic** (table wrappers, empty states, inputs) → `CoreComponents` (globally imported)
- **Domain-specific** (invoice badges, format helpers) → domain module (e.g., `InvoiceComponents`)
- **Single-use** or highly context-dependent → keep inline

### Component conventions

- Every component must have `@doc`, `@spec`, and declarative `attr`/`slot` annotations
- Support a `class` attr for caller customization when reasonable
- Use `slot :inner_block` for content projection
- Use `@rest` (`:global`) for forwarding HTML attributes like `data-testid`

See `docs/adr/0043-component-driven-ui.md` for the architectural decision.

## TDD Workflow

Every feature starts with a test:

1. **Red** — Write a failing test that describes the desired behaviour
2. **Green** — Write the minimum code to make it pass
3. **Refactor** — Clean up while keeping tests green

### Test structure

```elixir
defmodule KsefHub.Invoices.ParserTest do
  use ExUnit.Case, async: true

  alias KsefHub.Invoices.Parser

  describe "parse/1" do
    test "extracts seller and buyer from FA(3) XML" do
      xml = File.read!("test/support/fixtures/sample_income.xml")

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.seller_nip == "1234567890"
      assert invoice.buyer_name == "Acme Corp"
    end

    test "returns error for invalid XML" do
      assert {:error, :invalid_xml} = Parser.parse("<not-valid>")
    end
  end
end
```

### Test data with ExMachina

Use factories (`test/support/factory.ex`) for test data instead of inline `@valid_attrs` maps:

```elixir
import KsefHub.Factory

# Insert a persisted record with defaults
cred = insert(:credential)

# Override specific fields
cred = insert(:credential, nip: "9999999999", is_active: false)

# Build attrs map without inserting (for testing context functions)
attrs = params_for(:credential, nip: "1234567890")
{:ok, cred} = Credentials.create_credential(attrs)
```

Keep explicit attrs only when testing validation logic (e.g., missing required fields, invalid formats).

### Mocking with Mox

- Define behaviours for all external dependencies (KSeF API, pdf-renderer, invoice-extractor, invoice-classifier, xmlsec1)
- Use `Mox.defmock/2` in `test_helper.exs`
- Use `expect/3` for specific call expectations in tests
- Use `stub/3` for default returns in setup blocks
- Set `async: true` on tests that don't share state

### Test fixtures

Store sample FA(3) XML files in `test/support/fixtures/`. Include both valid invoices and edge cases (missing fields, multiple line items, different date formats).

## Project Conventions

### OpenAPI Documentation (required for every API endpoint)

Every REST API controller action **must** have an `open_api_spex` operation spec. This is NOT automatic — you must manually annotate each action.

When adding a new API endpoint:

1. Add `use OpenApiSpex.ControllerSpecs` to the controller (if not already present)
2. Define an `operation(:action_name, ...)` block above each action function
3. Create or reuse schemas under `lib/ksef_hub_web/schemas/` for request/response bodies
4. Verify the spec renders correctly at `/dev/swaggerui` (dev only)

```elixir
# In the controller:
use OpenApiSpex.ControllerSpecs

alias KsefHubWeb.Schemas
alias OpenApiSpex.Schema

tags(["TagName"])
security([%{"bearer" => []}])

operation(:index,
  summary: "Short summary",
  description: "Longer description of what this endpoint does.",
  parameters: [
    id: [in: :path, description: "Resource UUID.", schema: %Schema{type: :string, format: :uuid}]
  ],
  responses: %{
    200 => {"Success", "application/json", Schemas.SomeResponse},
    401 => {"Unauthorized", "application/json", Schemas.ErrorResponse}
  }
)

def index(conn, params) do
  # ...
end
```

Key files:
- `lib/ksef_hub_web/api_spec.ex` — root OpenAPI spec (info, security, servers)
- `lib/ksef_hub_web/schemas/` — reusable API schemas (Invoice, Token, response wrappers)
- Spec served at: `GET /api/openapi` (JSON)
- SwaggerUI at: `GET /dev/swaggerui` (dev only)

### ADR (Architecture Decision Records)

Every significant technical decision gets an ADR in `docs/adr/`:

```
docs/adr/NNNN-short-title.md
```

Format:
```markdown
# NNNN. Short Title

Date: YYYY-MM-DD

## Status
Accepted | Superseded by NNNN

## Context
Why this decision was needed.

## Decision
What we decided.

## Consequences
Trade-offs and implications.
```

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

### Rate limits

| Operation | Limit | Strategy |
|-----------|-------|----------|
| Invoice download | 8 req/s | Token bucket or `Process.sleep(125)` between requests |
| Query | 2 req/s | `Process.sleep(500)` between queries |

### Session management

- KSeF sessions have 1-hour TTL
- Always terminate sessions when done (don't let them expire)
- If session expires mid-sync, re-authenticate and continue
- One active session at a time per NIP

### FA(3) XML parsing

- Polish field names: `P_1` (issue date), `P_2` (sequential number), etc.
- Maintain a clear mapping from FA(3) field codes to domain field names
- Handle nested structures: `Podmiot1` (seller), `Podmiot2` (buyer), `Fa` (invoice data)
- Multiple date formats: ISO8601 with and without fractional seconds
- Test with real-world XML samples covering edge cases

## Useful References

| Resource | URL |
|----------|-----|
| KSeF Test Environment | https://ksef-test.mf.gov.pl |
| KSeF Production | https://ksef.mf.gov.pl |
| FA(3) Schema | http://crd.gov.pl/wzor/2025/06/25/13775/schemat.xsd |
| FA(3) Stylesheet | http://crd.gov.pl/wzor/2025/06/25/13775/styl.xsl |
