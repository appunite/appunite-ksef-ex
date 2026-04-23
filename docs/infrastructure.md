# Infrastructure Guide

Overview of deployment topology, CI/CD pipeline, cloud configuration, and sidecar service relationships for KSeF Hub.

---

## Topology Overview

```text
                        ┌──────────────────────────────────────────────┐
                        │         GCP Cloud Run (gen2)                 │
                        │         europe-west1 · scale 0–3             │
                        │                                              │
                        │  ┌───────────────────────────────────────┐  │
                        │  │ ksef-hub · port 4000                  │  │
                        │  │ Elixir/Phoenix release                 │  │
                        │  │ 512Mi RAM · 1 CPU · 80 concurrent req │  │
                        │  │ /healthz startup + liveness probes    │  │
                        │  └──────────────┬────────────────────────┘  │
                        │                 │ localhost                  │
                        │   ┌─────────────┼─────────────────────────┐ │
                        │   ▼             ▼             ▼            │ │
                        │ :3001         :3002         :3003           │ │
                        │ pdf-renderer  invoice-      invoice-        │ │
                        │ 256Mi/0.5CPU  extractor     classifier      │ │
                        │               512Mi/1CPU    512Mi/1CPU      │ │
                        │                             GCS FUSE ↓      │ │
                        └──────────────────────────────────────────────┘
                                  │                    │
                    ┌─────────────┤                    │
                    ▼             ▼                    ▼
              PostgreSQL    GCP Secret           GCS Bucket
              (Supabase)    Manager              au-ksef-ex-ml-models
                            (10 secrets)         (ML model weights)
```

All sidecars run in the same Cloud Run instance as the main app and communicate over **localhost** — no network-level authentication or TLS is required between them. Application-level bearer-token authentication is still enforced for the extractor and classifier endpoints; the pdf-renderer has no auth. The main container startup is gated on all three sidecars being healthy.

---

## Cloud Provider & Region

| Resource | Value |
|----------|-------|
| GCP project | `au-ksef-ex` |
| Primary region | `europe-west1` |
| Execution environment | Cloud Run **gen2** (required for GCS FUSE) |
| Artifact Registry repo | `europe-west1-docker.pkg.dev/au-ksef-ex/ksef-hub/` |
| Service account | `ksef-hub-runner@au-ksef-ex.iam.gserviceaccount.com` |
| Public URL | `https://invoices.appunite.com` |

---

## Database

> ADR: [0005 — PostgreSQL on Supabase](adr/0005-supabase-database.md)

PostgreSQL is managed by **Supabase**. The application uses plain Ecto — no Supabase-specific features, so the database is portable to any PostgreSQL host.

| Setting | Value |
|---------|-------|
| Host | Supabase-managed PostgreSQL |
| Connection | `DATABASE_URL` secret from GCP Secret Manager |
| Pool size (prod) | 5 (Cloud Run service) · configurable via `POOL_SIZE` |
| Pool size (default) | 10 |
| IPv6 | Enabled via `ECTO_IPV6=true` env var when using IPv6 Supabase endpoint |
| Primary keys | Binary UUIDs |
| Upsert strategy | `on_conflict: :replace_all` for invoice deduplication |

**Connection note:** Supabase session pooler URL format is used (not transaction pooler), because Oban requires persistent connections.

---

## Sidecar Services

For endpoint details, request/response formats, and error handling, see [docs/sidecar-services.md](sidecar-services.md).

### pdf-renderer — port 3001

> ADR: [0015 — KSeF PDF Microservice](adr/0015-ksef-pdf-microservice.md) · supersedes [0004 — PDF Generation via xsltproc + Gotenberg](adr/0004-pdf-generation-xsltproc.md)

Converts FA(3) XML invoices to PDF or HTML. Replaces the former xsltproc + Gotenberg pipeline.

| Property | Value |
|----------|-------|
| Image | `europe-west1-docker.pkg.dev/au-ksef-ex/ksef-hub/ksef-pdf:latest` |
| Source | Built from `appunite/ksef-pdf` GitHub repo (`feature/html-output` branch) during CI |
| Resources | 256Mi RAM · 0.5 CPU |
| Startup probe | `GET /health` · 3s delay · 3s period · 5 failures |
| Endpoints | `POST /generate/pdf` · `POST /generate/html` · `GET /health` |
| Auth | None (localhost only) |
| Env var (app) | `PDF_RENDERER_URL=http://localhost:3001` |

### invoice-extractor — port 3002

> ADR: [0017 — PDF Extraction Sidecar](adr/0017-unstructured-pdf-extraction-sidecar.md)

Extracts structured invoice data from uploaded PDFs using OCR (unstructured + poppler + tesseract) and Claude structured output.

| Property | Value |
|----------|-------|
| Image | `europe-west1-docker.pkg.dev/au-ksef-ex/ghcr-mirror/appunite/au-ksef-unstructured:latest` |
| Source | Mirrored from `ghcr.io/appunite/au-ksef-unstructured` |
| Resources | 512Mi RAM · 1 CPU |
| Startup probe | `GET /health` · 5s delay · 5s period · 10 failures |
| Endpoints | `POST /extract` (multipart PDF) |
| Auth | Bearer token via `INVOICE_EXTRACTOR_API_TOKEN` secret |
| Secrets | `ANTHROPIC_API_KEY` (Claude calls happen inside this sidecar) |
| Env vars (app) | `INVOICE_EXTRACTOR_URL=http://localhost:3002` · `INVOICE_EXTRACTOR_API_TOKEN` |

### invoice-classifier — port 3003

> ADR: [0019 — ML Prediction Sidecar](adr/0019-ml-prediction-sidecar.md) · [0028 — Classifier Sidecar with GCS Models](adr/0028-classifier-sidecar-gcs-models.md)

ML-based category and tag prediction using a LightGBM model. Model weights are loaded at startup from a GCS bucket via GCS FUSE.

| Property | Value |
|----------|-------|
| Image | `europe-west1-docker.pkg.dev/au-ksef-ex/ghcr-mirror/appunite/au-payroll-model-categories:latest` |
| Source | Mirrored from `ghcr.io/appunite/au-payroll-model-categories` |
| Resources | 512Mi RAM · 1 CPU |
| Startup probe | `GET /health` · 5s delay · 5s period · 10 failures |
| Liveness probe | `GET /health` · 30s period · 3 failures |
| Auth | Bearer token via `INVOICE_CLASSIFIER_API_TOKEN` secret (overridable per-company in Settings → Services) |
| Volume mount | `/app/models` ← `gs://au-ksef-ex-ml-models` (read-only, GCS FUSE) |
| Env vars (app) | `INVOICE_CLASSIFIER_URL=http://localhost:3003` · `INVOICE_CLASSIFIER_API_TOKEN` |
| Confidence threshold | ≥ 80% auto-applied; below threshold queued for manual review |

**GCS FUSE requirement:** The Cloud Run gen2 execution environment is mandatory — gen1 does not support GCS FUSE mounts.

---

## Image Registry

All production images live in **GCP Artifact Registry**. Cloud Run cannot pull directly from `ghcr.io`, so external images must be mirrored first.

| Image | Registry path |
|-------|--------------|
| Main app | `europe-west1-docker.pkg.dev/au-ksef-ex/ksef-hub/ksef-hub:{sha,latest}` |
| pdf-renderer | `europe-west1-docker.pkg.dev/au-ksef-ex/ksef-hub/ksef-pdf:{sha,latest}` |
| invoice-extractor | `europe-west1-docker.pkg.dev/au-ksef-ex/ghcr-mirror/appunite/au-ksef-unstructured:latest` |
| invoice-classifier | `europe-west1-docker.pkg.dev/au-ksef-ex/ghcr-mirror/appunite/au-payroll-model-categories:latest` |

**Mirroring new external images** — see `docs/sidecar-services.md` for the pull-tag-push procedure.

**Platform constraint:** All images must target `linux/amd64`. When building on Apple Silicon (M1/M2/M3) add `--platform linux/amd64` to `docker build`.

---

## Secrets (GCP Secret Manager)

All secrets are injected as environment variables at runtime via GCP Secret Manager. Never committed to the repo.

| GCP Secret Manager ID | Env var | Used by | Purpose |
|-----------------------|---------|---------|---------|
| `database-url` | `DATABASE_URL` | app, migration job | Supabase PostgreSQL connection string |
| `secret-key-base` | `SECRET_KEY_BASE` | app | Phoenix session signing |
| `google-client-id` | `GOOGLE_CLIENT_ID` | app | Google OAuth |
| `google-client-secret` | `GOOGLE_CLIENT_SECRET` | app | Google OAuth |
| `credential-encryption-key` | `CREDENTIAL_ENCRYPTION_KEY` | app | AES-256-GCM encryption for PKCS12 certs |
| `mailgun-signing-key` | `MAILGUN_SIGNING_KEY` | app | Inbound webhook verification |
| `mailgun-api-key` | `MAILGUN_API_KEY` | app | Outbound email sending |
| `invoice-extractor-api-token` | `INVOICE_EXTRACTOR_API_TOKEN` / `API_TOKEN` | app + extractor sidecar | Bearer auth between app and extractor |
| `invoice-classifier-api-token` | `INVOICE_CLASSIFIER_API_TOKEN` / `API_TOKEN` | app + classifier sidecar | Bearer auth between app and classifier |
| `anthropic-api-key` | `ANTHROPIC_API_KEY` | extractor sidecar | Claude API calls for PDF extraction |

---

## CI/CD Pipeline

Defined in `.github/workflows/ci.yml`. The workflow triggers on all pull requests and on pushes to `main`. The test job runs for both triggers; the deploy job runs only on pushes to `main` (gated on the test job).

### Test job (all branches)

```text
Checkout
  → Setup Elixir 1.18.4 / OTP 28.0.2
  → Restore deps + _build cache (keyed on mix.lock)
  → mix deps.get
  → mix format --check-formatted
  → mix compile --warnings-as-errors
  → mix credo --strict
  → mix test
       (PostgreSQL 16 service container, ksef_hub_test database)
```

### Deploy job (main branch only, after tests pass)

```text
GCP auth via Workload Identity Federation (no long-lived service account keys)
  → Setup Cloud SDK
  → Configure Docker for Artifact Registry
  → docker build + push main app image  (tagged :sha + :latest)
  → Build + push ksef-pdf sidecar image (from feature/html-output branch)
  → Run database migrations
       (Cloud Run job: ksef-hub-migrate · KsefHub.Release.migrate())
  → gcloud run services replace cloud-run/service.yaml
       (deploys new image SHA, applies full service config)
  → gcloud run services add-iam-policy-binding
       (ensures allUsers invoker role — idempotent)
```

**Concurrency:** The deploy job uses `concurrency: deploy-production` with `cancel-in-progress: false`, so concurrent pushes queue rather than cancel each other.

**Authentication:** Uses GCP Workload Identity Federation — no service account JSON key stored in GitHub secrets.

---

## Cloud Run Service Configuration

The canonical service definition lives in `cloud-run/service.yaml` (Knative v1 format). CI applies it on every deploy via `gcloud run services replace`.

Key settings:

| Setting | Value |
|---------|-------|
| Min instances | 0 (scales to zero when idle) |
| Max instances | 3 |
| Container concurrency | 80 requests per instance |
| Startup CPU boost | Enabled |
| Health check endpoint | `GET /healthz` |
| Startup probe | 5s initial delay · 5s period · 10 failure threshold |
| Liveness probe | 30s period · 3 failure threshold |
| Container startup order | ksef-hub depends on pdf-renderer, invoice-extractor, invoice-classifier |

---

## Operational Jobs

Two Cloud Run Jobs handle tasks that require Mix/Release functions outside the HTTP request cycle.

### ksef-hub-migrate (migration job)

Created and run automatically by CI on every deploy; it can also be triggered manually:

```bash
gcloud run jobs execute ksef-hub-migrate \
  --region europe-west1 \
  --wait \
  --args 'eval,KsefHub.Release.migrate()'
```

### ksef-hub-eval (ad-hoc eval job)

Defined in `.github/workflows/eval.yml`. Triggered manually via `workflow_dispatch` with an Elixir expression input. Defaults to `KsefHub.Release.reparse_ksef_invoices()`.

Configuration: 512Mi RAM · max 0 retries · 600s timeout · same secrets as the main service.

Use this for backfill operations, re-parsing, or any one-off `KsefHub.Release.*` calls. See `docs/operations.md` for available release tasks and usage examples.

---

## Local Development

Local environment uses Docker Compose to mirror the production sidecar topology:

```yaml
services:
  db:            postgres:17-alpine      (port 5432)
  pdf-renderer:  ghcr.io/appunite/ksef-pdf:latest         (port 3001)
  invoice-extractor: ghcr.io/appunite/au-ksef-unstructured:v0.1.0  (port 3002)
  invoice-classifier: ghcr.io/appunite/au-payroll-model-categories:latest (port 3003)
```

ML models are mounted from `./ml-models:/app/models:ro` (local directory, not GCS).

Environment variables are loaded from `.env` (copy from `.env.example`). See `README.md` for full setup instructions.

---

## Email (Mailgun)

> ADR: [0025 — Inbound Email Invoice Processing](adr/0025-inbound-email-invoice-processing.md)

Inbound and outbound email is handled by Mailgun.

| Direction | Mechanism |
|-----------|-----------|
| Inbound invoices | Mailgun routes → `POST /webhooks/mailgun/inbound` (per-company email address `<company-slug>@mg.payroll.appunite.co`) |
| Outbound | Swoosh + Mailgun API adapter (`MAILGUN_API_KEY`) |
| Webhook verification | HMAC signature check via `MAILGUN_SIGNING_KEY` |
| Domain | `mg.payroll.appunite.co` |

---

## Background Jobs (Oban)

> ADR: [0003 — Incremental Invoice Sync with Oban](adr/0003-incremental-sync-oban.md)

Oban workers run inside the main Phoenix process. Key scheduled jobs:

| Job | Schedule | Purpose |
|-----|----------|---------|
| `SyncWorker` | Every N minutes (configurable, default 60) | KSeF invoice sync per company |
| `ClassifierWorker` | On expense creation | ML category/tag prediction |
| Inbound email processing | On webhook receipt | PDF extraction + invoice creation |

`SYNC_INTERVAL_MINUTES` must be a divisor of 60 (valid: 1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30, 60).
