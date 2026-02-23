# 0019. ML Prediction Sidecar for Invoice Classification

Date: 2026-02-23

## Status

Accepted

## Context

Expense invoices need category and tag classification. Manual classification is time-consuming and inconsistent across reviewers. AppUnite has an existing ML model ([au-payroll-model-categories](https://github.com/appunite/au-payroll-model-categories)) trained on historical expense data, exposed as a FastAPI service with LightGBM (~200ms per prediction).

We need to decide how to integrate this model: embed it in the Elixir app, call it as a remote service, or run it as a sidecar.

## Decision

Run the ML prediction service as a Docker sidecar (same pattern as ksef-pdf), accessed via HTTP from an Oban background worker.

Key design decisions:

1. **Sidecar pattern** — The Python/LightGBM model runs in its own container (`ghcr.io/appunite/au-payroll-model-categories`), accessed via `POST /predict/category` and `POST /predict/tag`. This avoids embedding Python in the Elixir runtime and keeps the model independently deployable.

2. **Behaviour + Mox** — External service access through `KsefHub.Predictions.Behaviour` with `PredictionService` implementation, following the exact pattern established by `KsefHub.Pdf.Behaviour` + `KsefPdfService`.

3. **Confidence-based auto-apply** — Predictions at >= 80% confidence are auto-applied when a matching category/tag exists in the company. Below 80%, predictions are stored for human review. This balances automation speed with accuracy.

4. **Skip unmatched** — If the predicted category/tag name doesn't exist in the company's configured categories/tags, the prediction is stored but not applied, even at high confidence. This prevents creating phantom categories.

5. **Expenses only** — The model was trained on expense data, so predictions are only generated for expense invoices. Income invoices are skipped entirely.

6. **Asynchronous via Oban** — Predictions run in background jobs (default queue, max 3 attempts) triggered after invoice creation. This keeps invoice creation fast and handles transient prediction service failures with retries.

7. **Prediction fields on invoice** — Nine new columns store prediction metadata (status, predicted names, confidences, model version, full probability distributions, timestamp). These fields survive KSeF re-syncs (excluded from upsert replace fields).

8. **Manual override** — When a user manually sets a category or tag via the API, prediction_status is updated to "manual" to prevent re-prediction and signal human intent.

## Consequences

**Positive:**
- Automated classification reduces manual review workload
- Confidence scoring provides transparency into prediction quality
- Sidecar is independently deployable and scalable
- Full probability distributions stored for future UX (e.g., "Did you mean...?" suggestions)
- Graceful degradation — if the sidecar is down, invoices are created normally without predictions

**Negative:**
- Additional Docker service to manage in deployment (Cloud Run sidecar)
- ~200ms latency per prediction (mitigated by async execution)
- Prediction accuracy depends on model quality and company-specific training data
- Category/tag name matching is exact (no fuzzy matching) — model must predict names that exactly match company configuration

**Trade-offs:**
- 80% threshold is a starting point; may need tuning per company based on observed accuracy
- Storing full probability maps increases DB row size; excluded from list API responses for performance
