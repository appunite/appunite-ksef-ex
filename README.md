# KSeF Hub

Dedicated microservice for Poland's **National e-Invoice System (KSeF)**. Handles the complexity of KSeF integration — certificate authentication, XADES signing, FA(3) XML parsing, invoice sync, and PDF generation — exposing clean REST APIs for any consumer application.

## Why

Embedding KSeF complexity (certificate auth, XML parsing, rate limits, gov.pl stylesheets) into every consumer app is wrong. **KSeF Hub** owns it all in one place and provides simple APIs.

## Tech Stack

- **Elixir** + **Phoenix 1.8** (REST API + LiveView admin UI)
- **PostgreSQL** via Supabase + Ecto
- **xsltproc** — gov.pl XSL stylesheet transformation
- **xmlsec1** — XADES certificate signing
- **Gotenberg** — HTML to PDF conversion
- **Tailwind CSS** + **DaisyUI** — admin UI styling

## Getting Started

### Prerequisites

- Erlang 28+ / Elixir 1.18+ (see `.tool-versions`)
- PostgreSQL (or Supabase)
- `xsltproc` and `xmlsec1` for full functionality

### Setup

```bash
mix setup          # deps, DB, assets
mix phx.server     # http://localhost:4000
```

### Docker

```bash
make docker.build
make docker.up     # starts app + Gotenberg sidecar
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
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:4000/api/expenses
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

**PDF pipeline:** FA(3) XML → xsltproc (gov.pl XSL) → HTML → Gotenberg → PDF

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
- `docs/adr/` — Architecture Decision Records

## License

Private. All rights reserved.
