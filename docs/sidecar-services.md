# Sidecar Services

KSeF Hub delegates specialized processing to sidecar microservices running alongside the main Elixir application. Each sidecar runs as a separate container and is accessed over HTTP.

## Services

| Service | Purpose | Port | Repository | ADR |
|---------|---------|------|------------|-----|
| **pdf-renderer** | FA(3) XML → PDF/HTML rendering (matches official gov.pl portal) | 3001 | [appunite/ksef-pdf-generator](https://github.com/appunite/ksef-pdf-generator) | [0015](adr/0015-ksef-pdf-microservice.md) |
| **invoice-extractor** | PDF → structured JSON extraction (unstructured + Anthropic Claude) | 3002 | [emilwojtaszek/au-ksef-unstructured](https://github.com/emilwojtaszek/au-ksef-unstructured) | [0017](adr/0017-unstructured-pdf-extraction-sidecar.md) |
| **invoice-classifier** | Invoice category/tag classification (FastAPI + LightGBM) | 3003 | [appunite/au-payroll-model-categories](https://github.com/appunite/au-payroll-model-categories) | [0019](adr/0019-ml-prediction-sidecar.md) |

## Architecture

```text
┌─────────────────────────────────┐
│        KSeF Hub (Elixir)        │
│                                 │
│  KsefHub.PdfRenderer ──────────────► pdf-renderer (:3001)
│                                 │     XML → PDF/HTML
│                                 │
│  KsefHub.InvoiceExtractor ─────────► invoice-extractor (:3002)
│                                 │     PDF → structured JSON
│                                 │
│  KsefHub.InvoiceClassifier ────────► invoice-classifier (:3003)
│                                 │     Invoice category/tag classification
└─────────────────────────────────┘
```

## Integration Pattern

Each sidecar follows the same integration pattern in the Elixir app:

1. **Behaviour** — defines the contract (e.g., `KsefHub.PdfRenderer.Behaviour`, `KsefHub.InvoiceExtractor.Behaviour`)
2. **Client module** — production implementation that makes HTTP calls to the sidecar
3. **Mox mock** — test implementation configured in `config/test.exs`
4. **URL env var** — configures the sidecar address (e.g., `PDF_RENDERER_URL`, `INVOICE_EXTRACTOR_URL`)

## Environment Variables

| Variable | Service | Description |
|----------|---------|-------------|
| `PDF_RENDERER_URL` | pdf-renderer | Sidecar URL (e.g., `http://localhost:3001`) |
| `INVOICE_EXTRACTOR_URL` | invoice-extractor | Sidecar URL (e.g., `http://localhost:3002`) |
| `INVOICE_EXTRACTOR_API_TOKEN` | invoice-extractor | Bearer token for authentication |
| `INVOICE_CLASSIFIER_URL` | invoice-classifier | Sidecar URL (e.g., `http://localhost:3003`) |

## Running Locally

All sidecars are defined in `docker-compose.yml`:

```bash
docker compose up
```

## Adding a New Sidecar

1. Create the microservice with a `Dockerfile`, health check endpoint, and HTTP API
2. Add it to `docker-compose.yml` with a health check
3. Define an Elixir behaviour and client module in the appropriate context
4. Add a Mox mock in `test_helper.exs` and configure it in `config/test.exs`
5. Add the `*_URL` env var to `.env.example` and deployment config
6. Write an ADR documenting the decision
