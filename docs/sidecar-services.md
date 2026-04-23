# Sidecar & External Services

KSeF Hub delegates specialized processing to companion microservices. In production, all run as **sidecars** (containers in the same Cloud Run service), communicating over localhost.

## Services

| Service | Purpose | Deployment | Port | Repository |
|---------|---------|------------|------|------------|
| **pdf-renderer** | FA(3) XML → PDF/HTML rendering | Sidecar | 3001 | [appunite/ksef-pdf-generator](https://github.com/appunite/ksef-pdf-generator) |
| **invoice-extractor** | PDF → structured JSON extraction (Claude) | Sidecar | 3002 | [appunite/au-ksef-unstructured](https://github.com/appunite/au-ksef-unstructured) |
| **invoice-classifier** | Invoice category/tag classification (LightGBM) | Sidecar | 3003 | [appunite/au-payroll-model-categories](https://github.com/appunite/au-payroll-model-categories) |

## Architecture

```text
Cloud Run service: ksef-hub (gen2, GCS FUSE enabled)
┌───────────────────────────────────────────────────────────────────┐
│  ksef-hub (Elixir, :4000)                                         │
│                                                                   │
│  KsefHub.PdfRenderer ──────────────► pdf-renderer (:3001)         │
│                                                                   │
│  KsefHub.InvoiceExtractor ─────────► invoice-extractor (:3002)    │
│                                                                   │
│  KsefHub.InvoiceClassifier ────────► invoice-classifier (:3003)   │
│                                        │                          │
│                                        ▼                          │
│                                   /app/models (GCS FUSE mount)    │
│                                   ├── invoice_classifier.joblib   │
│                                   └── invoice_tag_classifier.joblib│
└───────────────────────────────────────────────────────────────────┘
                                        ▲
                                        │ read-only mount
                                        │
                              GCS: au-ksef-ex-ml-models
```

## Docker Images

All public images are hosted on **GitHub Container Registry (ghcr.io)**:

| Image | Source |
|-------|--------|
| `ghcr.io/appunite/ksef-pdf:latest` | [ksef-pdf-generator](https://github.com/appunite/ksef-pdf-generator) |
| `ghcr.io/appunite/au-ksef-unstructured:latest` | [au-ksef-unstructured](https://github.com/appunite/au-ksef-unstructured) |
| `ghcr.io/appunite/au-payroll-model-categories:latest` | [au-payroll-model-categories](https://github.com/appunite/au-payroll-model-categories) |

### Cloud Run and ghcr.io

Cloud Run **cannot pull directly from ghcr.io**. All sidecar images must be mirrored to GCP Artifact Registry before deployment:

```bash
# 1. Pull the amd64 image (required — Cloud Run only runs amd64/linux)
docker pull --platform linux/amd64 ghcr.io/appunite/ksef-pdf:latest
docker pull --platform linux/amd64 ghcr.io/appunite/au-ksef-unstructured:latest
docker pull --platform linux/amd64 ghcr.io/appunite/au-payroll-model-categories:latest

# 2. Tag for Artifact Registry
docker tag ghcr.io/appunite/ksef-pdf:latest \
  europe-west1-docker.pkg.dev/au-ksef-ex/ksef-hub/ksef-pdf:latest
docker tag ghcr.io/appunite/au-ksef-unstructured:latest \
  europe-west1-docker.pkg.dev/au-ksef-ex/ksef-hub/invoice-extractor:latest
docker tag ghcr.io/appunite/au-payroll-model-categories:latest \
  europe-west1-docker.pkg.dev/au-ksef-ex/ksef-hub/invoice-classifier:latest

# 3. Push to Artifact Registry
docker push europe-west1-docker.pkg.dev/au-ksef-ex/ksef-hub/ksef-pdf:latest
docker push europe-west1-docker.pkg.dev/au-ksef-ex/ksef-hub/invoice-extractor:latest
docker push europe-west1-docker.pkg.dev/au-ksef-ex/ksef-hub/invoice-classifier:latest
```

Or use the Makefile shortcut for the classifier:

```bash
make classifier.mirror
```

**Important:** If building on Apple Silicon (M-series), use `--platform linux/amd64` when pulling. ARM images will be rejected by Cloud Run.

## GCS Model Storage

The invoice-classifier requires ML model files (~18MB) at `/app/models`. In production, these are stored in a GCS bucket and mounted via Cloud Storage FUSE:

- **Bucket:** `gs://au-ksef-ex-ml-models`
- **Mount path:** `/app/models` (read-only)
- **Requires:** gen2 execution environment

### GCS setup (one-time)

```bash
# Create bucket
gsutil mb -l europe-west1 gs://au-ksef-ex-ml-models

# Upload initial models
gsutil cp ml-models/*.joblib gs://au-ksef-ex-ml-models/

# Grant read access to the Cloud Run service account
gcloud projects add-iam-policy-binding au-ksef-ex \
  --member="serviceAccount:ksef-hub-runner@au-ksef-ex.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"
```

## Updating ML Models

The invoice-classifier uses LightGBM models stored in a GCS bucket and mounted
at runtime. When you need to retrain or update models:

### Step-by-step

1. **Train new models** in the classifier repo:
   ```bash
   git clone git@github.com:appunite/au-payroll-model-categories.git /tmp/classifier
   cd /tmp/classifier
   make train
   ```

2. **Copy trained models** to this repo:
   ```bash
   cp /tmp/classifier/models/invoice_classifier.joblib ml-models/
   cp /tmp/classifier/models/invoice_tag_classifier.joblib ml-models/
   ```

3. **Upload to GCS and restart** the production service:
   ```bash
   make models.upload
   make models.restart
   ```

4. **Commit** the updated models:
   ```bash
   git add ml-models/
   git commit -m "chore: update ML models"
   ```

Or use `make models.train` to see these instructions at any time.

### How it works

- Models are stored in GCS bucket `gs://au-ksef-ex-ml-models`
- Cloud Run mounts the bucket at `/app/models` via GCS FUSE (read-only)
- The classifier container loads models on startup
- `make models.restart` triggers a new Cloud Run revision that re-mounts the bucket
- Models are also committed to the repo (via Git LFS) for reproducibility

## Environment Variables

### Main app (ksef-hub)

Sidecar configuration comes from environment variables (see below). The **invoice classifier** has a per-company override UI in **Settings → Services** (stored in the `classifier_configs` table), but the classification pipeline does not yet read those DB overrides — it still uses global `Application.get_env` settings (see `lib/ksef_hub/invoice_classifier.ex`). The per-company override UI is available but the runtime wiring is pending (see ADR-0049), so DB values do not currently take precedence over env vars.

| Variable | Service | Description |
|----------|---------|-------------|
| `PDF_RENDERER_URL` | pdf-renderer | Sidecar URL (default: `http://localhost:3001`) |
| `INVOICE_EXTRACTOR_URL` | invoice-extractor | Sidecar URL (default: `http://localhost:3002`) |
| `INVOICE_EXTRACTOR_API_TOKEN` | invoice-extractor | Bearer token for authentication |
| `INVOICE_CLASSIFIER_URL` | invoice-classifier | Sidecar URL (default: `http://localhost:3003`) |
| `INVOICE_CLASSIFIER_API_TOKEN` | invoice-classifier | Bearer token for authentication |

### Invoice extractor sidecar

| Variable | Description |
|----------|-------------|
| `PORT` | Listen port (set to `3002`) |
| `API_TOKEN` | Token for authenticating incoming requests |
| `ANTHROPIC_API_KEY` | Anthropic API key for Claude (used for PDF extraction). Model defaults are set in the container image. |

### Invoice classifier sidecar

| Variable | Description |
|----------|-------------|
| `PORT` | Listen port (set to `3003`) |
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
| `invoice-classifier-api-token` | `INVOICE_CLASSIFIER_API_TOKEN` / `API_TOKEN` | ksef-hub + classifier sidecar |
| `anthropic-api-key` | `ANTHROPIC_API_KEY` | extractor sidecar |

## Running Locally

All services are defined in `docker-compose.yml`:

```bash
docker compose up
```

Each service uses its dedicated port consistently across all environments:
- pdf-renderer: 3001
- invoice-extractor: 3002
- invoice-classifier: 3003

The classifier mounts `./ml-models` as a read-only volume, matching the GCS FUSE mount in production.

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
