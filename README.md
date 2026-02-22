# KSeF Hub

Dedicated microservice for Poland's **National e-Invoice System (KSeF)**. Handles the complexity of KSeF integration — certificate authentication, XADES signing, FA(3) XML parsing, invoice sync, and PDF generation — exposing clean REST APIs for any consumer application.

## Why

Embedding KSeF complexity (certificate auth, XML parsing, rate limits, gov.pl stylesheets) into every consumer app is wrong. **KSeF Hub** owns it all in one place and provides simple APIs.

## Tech Stack

- **Elixir** + **Phoenix 1.8** (REST API + LiveView admin UI)
- **PostgreSQL** via Supabase + Ecto
- **xmlsec1** — XADES certificate signing
- **ksef-pdf** — PDF + HTML generation microservice (ghcr.io/appunite/ksef-pdf)
- **Tailwind CSS** + **DaisyUI** — admin UI styling

## Getting Started

### Prerequisites

- Erlang 28+ / Elixir 1.18+ (see `.tool-versions`)
- PostgreSQL (or Supabase)
- `xmlsec1` for XADES signing

### Setup

```bash
mix setup          # deps, DB, assets
mix phx.server     # http://localhost:4000
```

### Configuration

Copy and configure environment variables:

```bash
cp .env.example .env
# Edit .env with your credentials:
# - DATABASE_URL
# - SECRET_KEY_BASE
# - KSEF_API_URL
# - GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET
# - KSEF_PDF_URL
# - CREDENTIAL_ENCRYPTION_KEY
```

See the full list in [`CLAUDE.md`](CLAUDE.md#environment-variables).

### Docker

```bash
make docker.build
make docker.up     # starts app + ksef-pdf sidecar
```

## Available Make Targets

```makefile
make help          # list all targets
make test          # run tests
make fmt           # format code
make lint          # credo --strict
make precommit     # format + compile warnings + tests
make server        # start dev server
make db.setup      # create + migrate + seed
make docker.build  # build Docker image
```

## API Overview

### Expense Invoices

```http
GET    /api/expenses          # list with filters
GET    /api/expenses/:id      # invoice details
POST   /api/expenses/:id/approve
POST   /api/expenses/:id/reject
GET    /api/expenses/:id/html # HTML preview
GET    /api/expenses/:id/pdf  # PDF download
```

### Income Invoices

```http
GET    /api/income            # list with filters
GET    /api/income/:id        # invoice details
```

### Authentication

All API endpoints require a Bearer token.

**Getting a token:**

1. Sign in to the admin UI at `http://localhost:4000` using your Google account
2. Navigate to **Settings > API Tokens**
3. Click **Generate Token**, give it a name, and copy the token immediately (it is shown only once)

Tokens are scoped to full read access. Revoke tokens from the same settings page.

**Using the token:**

```bash
curl -H "Authorization: Bearer <token>" http://localhost:4000/api/expenses
```

## Architecture

```text
┌─────────────────────────────────────────────┐
│              KSeF Hub (Phoenix)              │
│                                             │
│  LiveView UI    REST API    Sync Worker     │
│  (admin)        (/api/*)    (15-min cron)   │
└──────┬──────────────┬──────────────┬────────┘
       │              │              │
       ▼              ▼              ▼
   Google OAuth   API Tokens    KSeF API
                                (gov.pl)
       │              │              │
       └──────────────┴──────────────┘
                      │
                 PostgreSQL
                 (Supabase)
```

**PDF pipeline:** FA(3) XML → ksef-pdf microservice → PDF

## Project Structure

```text
lib/
├── ksef_hub/              # Business logic (contexts)
│   ├── invoices/          # Invoice CRUD, parsing, approval
│   ├── credentials/       # Certificate encryption & storage
│   ├── ksef_client/       # KSeF API communication
│   ├── pdf/               # PDF generation pipeline
│   └── sync_worker.ex     # Background sync GenServer
│
└── ksef_hub_web/          # Web layer
    ├── controllers/api/   # REST JSON endpoints
    ├── live/              # LiveView admin pages
    └── router.ex
```

## Documentation

- [`docs/prd.md`](docs/prd.md) — Product Requirements Document
- [`docs/sidecar-services.md`](docs/sidecar-services.md) — Sidecar microservices (ksef-pdf, au-ksef-unstructured)
- `docs/adr/` — Architecture Decision Records

## License

Private. All rights reserved.
