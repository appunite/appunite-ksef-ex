# 0028. Invoice Classifier as Cloud Run Sidecar with GCS-Mounted Models

Date: 2026-03-04

## Status

Accepted (supersedes deployment aspect of ADR 0019)

## Context

The invoice-classifier was originally planned as a separate Cloud Run service
(ADR 0019). However, `INVOICE_CLASSIFIER_URL=http://localhost:3003` was
configured in `cloud-run/service.yaml` without a corresponding sidecar
container, causing `econnrefused` errors in production.

The classifier is a lightweight LightGBM model (~18MB) that performs
category/tag prediction on invoice text. It needs model files at `/app/models`
at runtime. Options considered:

1. **Separate Cloud Run service** — original plan. Requires HTTPS between
   services, VPC configuration, and separate scaling/billing.
2. **Sidecar with baked-in models** — simple but requires image rebuild on
   every model update.
3. **Sidecar with GCS-mounted models** — models stored in GCS, mounted via
   Cloud Storage FUSE. Decouples model updates from image builds.

## Decision

Run the invoice-classifier as a **sidecar container** in the ksef-hub Cloud Run
service, with ML models mounted from a GCS bucket via Cloud Storage FUSE.

Key details:
- **Execution environment:** gen2 (required for GCS FUSE)
- **GCS bucket:** `gs://au-ksef-ex-ml-models`
- **Mount path:** `/app/models` (read-only)
- **Resources:** 1Gi memory, 1 CPU (LightGBM inference needs headroom)
- **Model files tracked** in repo via Git LFS for reproducibility
- **CI mirrors** the classifier image from ghcr.io to Artifact Registry

Model update workflow:
1. Train models in the classifier repo
2. Copy `.joblib` files to `ml-models/`
3. `make models.upload` to push to GCS
4. `make models.restart` to trigger new Cloud Run revision
5. Commit models to repo (Git LFS)

## Consequences

**Benefits:**
- Eliminates localhost/HTTPS mismatch — sidecar communicates over localhost
- No VPC or service-to-service auth complexity
- Model updates don't require image rebuilds
- Models versioned in repo (Git LFS) for reproducibility
- Single Cloud Run service simplifies billing and scaling

**Trade-offs:**
- Requires gen2 execution environment (slightly higher cold start)
- GCS FUSE adds small latency on first model read (~1-2s at startup)
- Sidecar shares resource quota with main app (mitigated by explicit limits)
- Git LFS required for model files (~18MB)

**Migration:**
- The standalone `invoice-classifier` Cloud Run service can be deleted after
  verifying the sidecar works correctly
