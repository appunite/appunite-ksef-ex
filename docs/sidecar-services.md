# Sidecar & External Services

KSeF Hub delegates specialized processing to companion microservices. In production, some run as **sidecars** (containers in the same Cloud Run service) and others as **separate Cloud Run services**.

## Services

| Service | Purpose | Deployment | Port | Repository |
|---------|---------|------------|------|------------|
| **pdf-renderer** | FA(3) XML → PDF/HTML rendering | Sidecar | 3001 | [appunite/ksef-pdf-generator](https://github.com/appunite/ksef-pdf-generator) |
| **invoice-extractor** | PDF → structured JSON extraction (Claude) | Sidecar | 8082 (prod) / 3002 (local) | [appunite/au-ksef-unstructured](https://github.com/appunite/au-ksef-unstructured) |
| **invoice-classifier** | Invoice category/tag classification (LightGBM) | Separate service | 3003 (local) / HTTPS (prod) | [appunite/au-payroll-model-categories](https://github.com/appunite/au-payroll-model-categories) |

## Architecture

```text
Cloud Run service: ksef-hub
┌──────────────────────────────────────────────────────────┐
│  ksef-hub (Elixir, :4000)                                │
│                                                          │
│  KsefHub.PdfRenderer ──────────► pdf-renderer (:3001)    │
│                                                          │
│  KsefHub.InvoiceExtractor ────► invoice-extractor (:8082)│
│                                                          │
└──────────────────────────────────────────────────────────┘
         │
         │  HTTPS
         ▼
┌──────────────────────────────────────────────────────────┐
│  Cloud Run service: invoice-classifier                   │
│  KsefHub.InvoiceClassifier ──► invoice-classifier (:8080)│
└──────────────────────────────────────────────────────────┘
```

## Docker Images

All public images are hosted on **GitHub Container Registry (ghcr.io)**:

| Image | Source |
|-------|--------|
| `ghcr.io/appunite/ksef-pdf:latest` | [ksef-pdf-generator](https://github.com/appunite/ksef-pdf-generator) |
| `ghcr.io/appunite/au-ksef-unstructured:latest` | [au-ksef-unstructured](https://github.com/appunite/au-ksef-unstructured) |
| `ghcr.io/appunite/au-payroll-model-categories:latest` | [au-payroll-model-categories](https://github.com/appunite/au-payroll-model-categories) (private — model is confidential) |

### Cloud Run and ghcr.io

Cloud Run **cannot pull directly from ghcr.io**. Sidecar images must be mirrored to GCP Artifact Registry:

```bash
# 1. Pull the amd64 image (required — Cloud Run only runs amd64/linux)
docker pull --platform linux/amd64 ghcr.io/appunite/ksef-pdf:latest
docker pull --platform linux/amd64 ghcr.io/appunite/au-ksef-unstructured:latest

# 2. Tag for Artifact Registry
docker tag ghcr.io/appunite/ksef-pdf:latest \
  europe-west1-docker.pkg.dev/au-ksef-ex/ksef-hub/ksef-pdf:latest
docker tag ghcr.io/appunite/au-ksef-unstructured:latest \
  europe-west1-docker.pkg.dev/au-ksef-ex/ksef-hub/invoice-extractor:latest

# 3. Push to Artifact Registry
docker push europe-west1-docker.pkg.dev/au-ksef-ex/ksef-hub/ksef-pdf:latest
docker push europe-west1-docker.pkg.dev/au-ksef-ex/ksef-hub/invoice-extractor:latest
```

**Important:** If building on Apple Silicon (M-series), use `--platform linux/amd64` when pulling. ARM images will be rejected by Cloud Run.

The invoice-classifier is deployed as a separate Cloud Run service and pulls its own image directly during deployment.

## Environment Variables

### Main app (ksef-hub)

| Variable | Service | Description |
|----------|---------|-------------|
| `PDF_RENDERER_URL` | pdf-renderer | Sidecar URL (`http://localhost:3001`) |
| `INVOICE_EXTRACTOR_URL` | invoice-extractor | Sidecar URL (`http://localhost:8082` in prod, `http://localhost:3002` locally) |
| `INVOICE_EXTRACTOR_API_TOKEN` | invoice-extractor | Bearer token for authentication |
| `INVOICE_CLASSIFIER_URL` | invoice-classifier | Service URL (`http://localhost:3003` locally, `https://invoice-classifier-*.run.app` in prod) |
| `INVOICE_CLASSIFIER_API_TOKEN` | invoice-classifier | Bearer token for authentication |

### Invoice extractor sidecar

| Variable | Description |
|----------|-------------|
| `PORT` | Listen port (set to `8082` in prod to avoid conflicts) |
| `API_TOKEN` | Token for authenticating incoming requests |
| `ANTHROPIC_API_KEY` | Anthropic API key for Claude (used for PDF extraction) |
| `ANTHROPIC_MODEL` | Claude model to use (e.g., `claude-sonnet-4-5-20250929`) |

### Invoice classifier service

| Variable | Description |
|----------|-------------|
| `API_TOKEN` | Token for authenticating incoming requests |

## GCP Secret Manager

Sensitive values are stored in Secret Manager and mounted as env vars in Cloud Run:

| Secret Name | Maps to | Used by |
|-------------|---------|---------|
| `database-url` | `DATABASE_URL` | ksef-hub |
| `secret-key-base` | `SECRET_KEY_BASE` | ksef-hub |
| `google-client-id` | `GOOGLE_CLIENT_ID` | ksef-hub |
| `google-client-secret` | `GOOGLE_CLIENT_SECRET` | ksef-hub |
| `credential-encryption-key` | `CREDENTIAL_ENCRYPTION_KEY` | ksef-hub |
| `mailgun-signing-key` | `MAILGUN_SIGNING_KEY` | ksef-hub |
| `mailgun-api-key` | `MAILGUN_API_KEY` | ksef-hub |
| `invoice-extractor-api-token` | `INVOICE_EXTRACTOR_API_TOKEN` / `API_TOKEN` | ksef-hub + extractor sidecar |
| `invoice-classifier-api-token` | `INVOICE_CLASSIFIER_API_TOKEN` | ksef-hub |
| `anthropic-api-key` | `ANTHROPIC_API_KEY` | extractor sidecar |

## Running Locally

All services are defined in `docker-compose.yml`:

```bash
docker compose up
```

Locally, port mapping handles the differences:
- pdf-renderer: container port 3001 → host port 3001
- invoice-extractor: container port 8080 → host port 3002
- invoice-classifier: container port 8080 → host port 3003

## Updating Sidecar Images in Production

When a new version of a sidecar image is released:

1. Pull the new amd64 image from ghcr.io
2. Tag and push to Artifact Registry (see commands above)
3. Deploy the updated service YAML or trigger a new Cloud Run revision

## Integration Pattern

Each service follows the same integration pattern in the Elixir app:

1. **Behaviour** — defines the contract (e.g., `KsefHub.PdfRenderer.Behaviour`)
2. **Client module** — production implementation that makes HTTP calls
3. **Mox mock** — test implementation configured in `config/test.exs`
4. **URL env var** — configures the service address
5. **Token env var** — optional bearer token for authentication (extractor + classifier)
