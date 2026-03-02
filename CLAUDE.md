# KSeF Hub

Dedicated service for Poland's National e-Invoice System (KSeF). Owns all KSeF complexity — certificate authentication, XADES signing, FA(3) XML parsing, invoice sync, PDF generation — and exposes clean REST APIs for any consumer application.

See `docs/prd.md` for full product requirements.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Elixir 1.16+ / OTP 26+ |
| Framework | Phoenix 1.8 + LiveView |
| Database | PostgreSQL (Supabase) via Ecto |
| Auth (UI) | Google Sign-In (company membership RBAC) |
| Auth (API) | Bearer API tokens (hashed, revocable) |
| PDF renderer | pdf-renderer sidecar (ghcr.io/appunite/ksef-pdf) |
| Invoice extractor | invoice-extractor sidecar (ghcr.io/appunite/au-ksef-unstructured) |
| Invoice classifier | Separate Cloud Run service (ghcr.io/appunite/au-payroll-model-categories) |
| XADES signing | xmlsec1 (CLI, called via System.cmd) |
| Background jobs | Oban (async workers, 60-min sync cron) |
| API docs | open_api_spex (OpenAPI 3.0 + SwaggerUI) |
| UI styling | Tailwind CSS + DaisyUI |
| Deployment | Docker, GCP Cloud Run |

## Project Structure

```
lib/
├── ksef_hub/                     # Business logic (contexts)
│   ├── invoices/                 # Invoice context (income + expense)
│   ├── credentials/              # Certificate storage & encryption
│   ├── ksef_client/              # KSeF API client (auth, query, download)
│   ├── invoice_classifier/       # ML classification sidecar client + Oban worker
│   ├── invoice_extractor/        # PDF extraction via invoice-extractor sidecar
│   ├── pdf_renderer/             # PDF/HTML generation via pdf-renderer sidecar
│   ├── sync_worker.ex            # GenServer — 60-min sync cron
│
└── ksef_hub_web/                 # Web layer
    ├── controllers/api/          # REST JSON controllers
    │   ├── expense_controller.ex
    │   └── income_controller.ex
    ├── live/                     # LiveView pages (admin UI)
    │   ├── dashboard_live.ex
    │   ├── invoice_live.ex
    │   └── certificate_live.ex
    └── router.ex

test/
├── ksef_hub/                     # Context unit tests
├── ksef_hub_web/                 # Controller & LiveView tests
├── support/                      # Fixtures, factories, mocks
│   └── fixtures/                 # Sample FA(3) XML files
└── test_helper.exs

docs/
├── prd.md                        # Product requirements
└── adr/                          # Architecture Decision Records
    ├── 0001-use-elixir.md
    └── ...
```

## Build & Run

```bash
# Install dependencies
mix deps.get

# Create and migrate database
mix ecto.setup

# Run the server (with LiveView)
mix phx.server

# Interactive console
iex -S mix phx.server
```

### Docker

```bash
# Build image
docker build -t ksef-hub .

# Run with Gotenberg sidecar (for PDF generation)
docker compose up
```

### System dependencies (required in Docker and CI)

```bash
apt-get install -y xmlsec1
```

## Tests

```bash
# Run all tests
mix test

# Run a specific test file
mix test test/ksef_hub/invoices_test.exs

# Run a specific test by line number
mix test test/ksef_hub/invoices_test.exs:42

# Run with coverage
mix test --cover

# Run integration tests (excluded by default, requires KSeF credentials)
mix test --include integration
# or
make test.integration
```

### Linting & formatting

```bash
# Format code (check)
mix format --check-formatted

# Static analysis
mix credo --strict

# Dialyzer (type checking)
mix dialyzer
```

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
| `KsefHub.InvoiceClassifier` | ML-based category/tag classification via invoice-classifier sidecar |
| `KsefHub.Accounts` | API token generation, validation, usage tracking |

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

## Environment Variables

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string (Supabase) |
| `SECRET_KEY_BASE` | Phoenix secret key (also used to derive encryption key) |
| `CREDENTIAL_ENCRYPTION_KEY` | Base64-encoded 32-byte AES-256 key for certificate encryption at rest. Falls back to `SHA256(SECRET_KEY_BASE)` if not set |
| `GOOGLE_CLIENT_ID` | Google OAuth client ID |
| `GOOGLE_CLIENT_SECRET` | Google OAuth client secret |
| `PDF_RENDERER_URL` | PDF renderer sidecar URL (e.g., `http://localhost:3001`) |
| `INVOICE_EXTRACTOR_URL` | Invoice extractor sidecar URL (e.g., `http://localhost:3002`) |
| `INVOICE_EXTRACTOR_API_TOKEN` | Bearer token for invoice-extractor authentication |
| `KSEF_API_URL` | KSeF v2 API URL (`https://api-test.ksef.mf.gov.pl` for test, `https://api.ksef.mf.gov.pl` for production) |
| `INVOICE_CLASSIFIER_URL` | Invoice classifier service URL (e.g., `http://localhost:3003` locally, `https://invoice-classifier-*.run.app` in prod) |
| `INVOICE_CLASSIFIER_API_TOKEN` | Bearer token for invoice-classifier authentication |
| `SYNC_INTERVAL_MINUTES` | KSeF sync cron interval in minutes (default: `60`) |
| `INBOUND_EMAIL_DOMAIN` | Domain for inbound email addresses (e.g., `mg.payroll.appunite.co`) |
| `MAILGUN_SIGNING_KEY` | Mailgun webhook signing key for verifying inbound emails |
| `MAILGUN_API_KEY` | Mailgun API key for sending emails |
| `MAILGUN_DOMAIN` | Mailgun sending domain (e.g., `mg.payroll.appunite.co`) |

## Useful References

| Resource | URL |
|----------|-----|
| KSeF Test Environment | https://ksef-test.mf.gov.pl |
| KSeF Production | https://ksef.mf.gov.pl |
| FA(3) Schema | http://crd.gov.pl/wzor/2025/06/25/13775/schemat.xsd |
| FA(3) Stylesheet | http://crd.gov.pl/wzor/2025/06/25/13775/styl.xsl |
