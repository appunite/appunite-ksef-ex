# KSeF Hub

Dedicated microservice for Poland's **National e-Invoice System (KSeF)**. Handles the complexity of KSeF integration — certificate authentication, XADES signing, FA(3) XML parsing, invoice sync, ML-based categorization, PDF generation — exposing clean REST APIs and a LiveView admin UI.

## Why

Embedding KSeF complexity (certificate auth, XADES signing, XML parsing, rate limits, gov.pl stylesheets) into every consumer app is wrong. **KSeF Hub** owns it all in one place and provides simple APIs.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Elixir 1.18+ / OTP 28+ |
| Framework | Phoenix 1.8 + LiveView |
| Database | PostgreSQL via Ecto |
| Auth (UI) | Google OAuth + email/password |
| Auth (API) | Bearer API tokens (hashed, revocable) |
| Background jobs | Oban (async workers, scheduled sync) |
| XADES signing | xmlsec1 (CLI) |
| API docs | OpenAPI 3.0 via open_api_spex + SwaggerUI |
| UI styling | Tailwind CSS + DaisyUI |
| Deployment | Docker, GCP Cloud Run |

### Sidecar Services

| Service | Image | Repository | Purpose |
|---------|-------|------------|---------|
| **pdf-renderer** | `ghcr.io/appunite/ksef-pdf` | [ksef-pdf-generator](https://github.com/appunite/ksef-pdf-generator) | FA(3) XML → PDF/HTML rendering |
| **invoice-extractor** | `ghcr.io/appunite/au-ksef-unstructured` | [au-ksef-unstructured](https://github.com/appunite/au-ksef-unstructured) | PDF → structured invoice data extraction |
| **invoice-classifier** | `ghcr.io/appunite/au-payroll-model-categories` | [au-payroll-model-categories](https://github.com/appunite/au-payroll-model-categories) | ML-based category/tag classification |

See [`docs/sidecar-services.md`](docs/sidecar-services.md) for integration details.

## Getting Started

### Prerequisites

- Erlang 28+ / Elixir 1.18+ (see `.tool-versions`)
- PostgreSQL
- `xmlsec1` for XADES signing (`apt-get install -y xmlsec1` on Debian/Ubuntu)

### Setup

```bash
mix setup          # deps, DB, assets
mix phx.server     # http://localhost:4000
```

### Configuration

```bash
cp .env.example .env
```

Key variables (see `.env.example` for the full list):

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Phoenix secret key |
| `CREDENTIAL_ENCRYPTION_KEY` | Base64-encoded 32-byte AES-256 key for certificate encryption at rest |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Google OAuth credentials |
| `KSEF_API_URL` | KSeF API URL (`https://api-test.ksef.mf.gov.pl` for test) |
| `PDF_RENDERER_URL` | PDF renderer sidecar URL (default: `http://localhost:3001`) |
| `INVOICE_EXTRACTOR_URL` | Invoice extractor sidecar URL (default: `http://localhost:3002`) |
| `INVOICE_CLASSIFIER_URL` | Invoice classifier sidecar URL (default: `http://localhost:3003`) |
| `MAILGUN_SIGNING_KEY` | Mailgun webhook signing key (for inbound email) |

### Docker

```bash
make docker.build  # build app image
make docker.up     # starts db + all sidecar services
```

## Make Targets

```
make help            # list all targets
make test            # run tests
make test.integration # run integration tests (requires KSeF credentials)
make fmt             # format code
make lint            # credo --strict
make dialyzer        # type checking
make precommit       # format + compile warnings + tests
make server          # start dev server
make console         # start dev server with IEx
make db.setup        # create + migrate + seed
make db.migrate      # run pending migrations
make db.reset        # drop + setup
make docker.build    # build Docker image
make docker.up       # start all services (docker compose)
make docker.down     # stop all services
```

To run a specific file or test by line number:

```bash
mix test test/ksef_hub/invoices_test.exs
mix test test/ksef_hub/invoices_test.exs:42
```

## API

All API endpoints require a Bearer token. Full OpenAPI spec available at `/api/openapi` and SwaggerUI at `/dev/swaggerui` (dev only).

### Authentication

1. Sign in to the admin UI at `http://localhost:4000`
2. Navigate to **Tokens** in the sidebar
3. Generate a token and copy it immediately (shown only once)

```bash
curl -H "Authorization: Bearer <token>" http://localhost:4000/api/invoices
```

### API Documentation

All REST endpoints are documented with OpenAPI 3.0 specs (via `open_api_spex`):

- `GET /api/openapi` — raw OpenAPI 3.0 JSON spec
- `GET /dev/swaggerui` — interactive SwaggerUI (dev only)

Run `mix phx.server` and visit [http://localhost:4000/dev/swaggerui](http://localhost:4000/dev/swaggerui) to browse the API interactively.

## Architecture

```text
┌──────────────────────────────────────────────────────────┐
│                   KSeF Hub (Phoenix)                     │
│                                                          │
│  LiveView UI    REST API    Oban Workers    Webhooks     │
│  (admin)        (/api/*)    (sync, classify)(Mailgun)    │
└──────┬────────────┬────────────┬──────────────┬──────────┘
       │            │            │              │
       ▼            ▼            ▼              ▼
  Google OAuth   API Tokens   KSeF API    Inbound Email
  Email/Pass                  (gov.pl)    (PDF extraction)
       │            │            │              │
       └────────────┴────────────┴──────────────┘
                         │
                    PostgreSQL
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
    pdf-renderer   invoice-ext.   invoice-cls.
      (PDF/HTML)   (PDF→JSON)    (ML categories)
```

### Key Flows

**Invoice Sync (Oban, every 60 min per company):** Load certificate → XADES authenticate → query invoice headers (incremental, since last checkpoint) → download each XML (rate-limited) → parse FA(3) → upsert to DB → advance checkpoint → terminate session.

**PDF Generation:** FA(3) XML → ksef-pdf sidecar → PDF/HTML.

**Inbound Email:** Mailgun webhook → signature verification → NIP extraction → invoice-extractor sidecar (PDF → structured data) → invoice creation.

**Invoice Classification (Oban, on expense creation):** New expense invoice → ClassifierWorker → invoice-classifier sidecar → auto-assign category/tags.

## Project Structure

```text
lib/
├── ksef_hub/                  # Business logic (contexts)
│   ├── invoices/              # Invoice CRUD, parsing, approval, categories, tags
│   ├── credentials/           # Certificate encryption, storage, PKCS12 parsing
│   ├── ksef_client/           # KSeF API client (auth, query, download)
│   ├── sync/                  # Oban sync workers, checkpoints, dispatching
│   ├── invoice_classifier/    # ML classification sidecar client + Oban worker
│   ├── pdf_renderer/          # PDF/HTML generation via pdf-renderer sidecar
│   ├── invoice_extractor/     # PDF extraction via invoice-extractor sidecar
│   ├── inbound_email/         # Mailgun webhook processing + Oban worker
│   ├── companies/             # Multi-company support, memberships
│   ├── accounts/              # Users, API tokens
│   ├── invitations/           # Company invitation system
│   └── xades_signer/          # xmlsec1 CLI wrapper for XADES signing
│
└── ksef_hub_web/              # Web layer
    ├── controllers/api/       # REST JSON controllers
    ├── live/                  # LiveView admin pages (18 modules)
    ├── schemas/               # OpenAPI request/response schemas
    ├── plugs/                 # Auth middleware
    └── router.ex
```

## Landing Page

Public marketing site lives in [`landing/`](landing/) — a standalone **Astro 5 + Tailwind v4 + TypeScript** project with i18n (Polish default, English alternate). **No coupling to the Phoenix app**: separate build, separate deploy, separate container.

Deployed automatically to GitHub Pages by [`.github/workflows/landing.yml`](.github/workflows/landing.yml) whenever `landing/**` changes. The Elixir `ci.yml` ignores landing-only diffs.

```bash
cd landing
npm install
npm run dev        # http://localhost:4321/appunite-ksef-ex/
npm run build      # → landing/dist/
```

See [`landing/README.md`](landing/README.md) for component structure and i18n conventions. For Claude Code conventions inside that folder, see [`landing/CLAUDE.md`](landing/CLAUDE.md).

## Documentation

- [`docs/prd.md`](docs/prd.md) — Product Requirements Document
- [`docs/sidecar-services.md`](docs/sidecar-services.md) — Sidecar microservices architecture
- [`docs/ksef-certificates.md`](docs/ksef-certificates.md) — Certificate handling guide
- `docs/adr/` — Architecture Decision Records (25 ADRs)

## License

Private. All rights reserved.
