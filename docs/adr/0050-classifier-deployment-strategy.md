---
name: Classifier Deployment Strategy
description: Exploration of multi-tenant ML model serving strategies — managed training with flexible deployment (self-hosted or managed).
tags: [classifier, ml, multi-tenant, architecture, deployment]
author: emil
date: 2026-04-24
status: Proposed
---

# 0050. Classifier Deployment Strategy

Date: 2026-04-24

## Status

Proposed — open for discussion, not yet decided.

## Context

KSeF Hub uses three sidecar services:

| Service | Coupling | Tenant-specific? |
|---------|----------|-----------------|
| **pdf-renderer** | Tightly coupled to the app (FA(3) XML → PDF) | No — same logic for all tenants |
| **invoice-extractor** | Tightly coupled to the app (PDF → structured JSON) | No — generic extraction |
| **invoice-classifier** | Loosely coupled, depends on tenant data | **Yes** — categories, tags, and classification patterns are per-company |

The classifier is fundamentally different: its accuracy depends on the tenant's own data. A model trained on one company's invoices (e.g., a media agency) will mis-classify for another (e.g., a construction firm). This means multi-tenant SaaS needs per-tenant models.

### Current state

- Single classifier service behind a per-company config (ADR 0049)
- Each company can override the classifier URL, token, and confidence thresholds
- One shared model serves all companies — predictions degrade as company profiles diverge
- Training data export exists (CSV with extended columns from the Services tab)

### Problem

As we scale to more tenants, a shared model won't work. We need a strategy for:
1. **Training** — how per-tenant models are created and updated
2. **Serving** — how predictions are served at inference time
3. **Cost** — who pays for compute (us or the tenant)
4. **Ops** — how much operational burden falls on us vs. the tenant

## Options Considered

### Option A — Managed multi-tenant model serving

We own both training and serving. A model-management sidecar loads per-tenant models on demand.

**How it works:**
- Tenant clicks "retrain" in the UI (or we auto-retrain on a schedule)
- We train the model from their approved invoices using our training pipeline
- A model-serving sidecar keeps recently-used models in memory, evicts cold ones
- Prediction requests are routed to the correct tenant model

**Pros:**
- Best UX — tenant never touches infrastructure
- We control model quality, versioning, rollback
- Can optimize hardware (shared GPU/CPU, model caching)

**Cons:**
- Operational complexity — cache eviction, cold starts, memory pressure, OOM risk
- We bear infra cost per model (though classification models are small, ~MBs)
- Single point of failure — our serving layer goes down, all tenants lose classification

### Option B — Dedicated self-hosted service per tenant

We open-source the classifier. Each tenant trains and deploys their own instance.

**How it works:**
- We provide training tools and a Docker image
- Tenant deploys to their own cloud (GCP Cloud Run, AWS ECS, etc.)
- Tenant configures their classifier URL in KSeF Hub (already supported via ADR 0049)

**Pros:**
- Zero infra cost for us
- Tenant data never leaves their environment (compliance/GDPR win)
- Tenant has full control over model, hardware, scaling

**Cons:**
- Terrible UX — requires cloud knowledge, deployment pipeline, monitoring
- Support burden when tenant's service breaks
- Fragmented versions — tenants may run stale images

### Option C — Managed training + flexible deployment (preferred direction)

We own the training pipeline. The tenant chooses where to serve: our managed infrastructure or their own cloud.

**How it works:**
- **Training**: We provide a managed training pipeline. Tenant's approved invoices feed into it. We produce a model artifact (e.g., ONNX, TensorFlow SavedModel, scikit-learn pickle).
- **Deployment option 1 — Managed**: We host the model in our serving layer (same as Option A). Included in the subscription or as a paid tier.
- **Deployment option 2 — Self-hosted on cloud ML platforms**: Tenant deploys the model artifact to a managed ML service:
  - **Google Cloud**: Vertex AI Endpoints (upload model → get prediction API), Cloud Run (containerized)
  - **AWS**: SageMaker Endpoints (upload model → get prediction API), Lambda (lightweight)
  - **Azure**: Azure ML Endpoints
- We provide clear documentation/tooling for each cloud platform deployment.
- Tenant points their classifier URL to their deployed endpoint (ADR 0049 already supports this).

**Pros:**
- We own the hardest part (training pipeline, data prep, feature engineering)
- Tenant gets a simple choice: "we host it" or "you host it on [GCP/AWS/Azure]"
- Cloud ML platforms handle scaling, monitoring, versioning natively
- Self-hosted option satisfies compliance-sensitive tenants
- Model artifact is portable — not locked to our infrastructure

**Cons:**
- Need to support multiple model export formats (or standardize on one like ONNX)
- Documentation/guides needed for each cloud platform
- Two code paths for model delivery (managed vs. self-hosted)

## Open Questions

1. **Model format**: What format do we standardize on? ONNX is portable but may lose framework-specific optimizations. scikit-learn pickle is simple but Python-only.
2. **Retraining frequency**: On-demand (tenant clicks button), scheduled (weekly), or continuous (on every N new approved invoices)?
3. **Minimum training data**: How many approved invoices does a company need before a per-tenant model outperforms the shared default model?
4. **Cold start**: For new tenants with no data, do we use a shared "bootstrap" model trained on anonymized cross-tenant data?
5. **Pricing**: Is managed serving included in the base plan, or a paid add-on?
6. **Model versioning**: How do we handle A/B testing between model versions? Rollback on accuracy regression?

## Decision

Not yet decided. This ADR captures the current thinking to be revisited when we approach multi-tenant scaling.

**Leaning toward Option C** — managed training with flexible deployment. It gives us the best of both worlds: great UX for tenants who want "it just works", and full control for tenants with compliance requirements or existing cloud infrastructure.

## Next Steps

- [ ] Research Vertex AI / SageMaker model deployment APIs — what's the minimal integration?
- [ ] Prototype: export a trained model artifact, deploy to Vertex AI, verify prediction API compatibility
- [ ] Define minimum viable training pipeline (how many invoices, what features, what accuracy threshold)
- [ ] Estimate serving costs per tenant for the managed option
- [ ] Decide on model format standard

## Consequences

Deferring this decision is acceptable for now — the current shared model + per-company config (ADR 0049) works for early tenants. But this becomes blocking when:
- A second tenant with a very different business profile onboards
- Classification accuracy drops below the confidence thresholds for any company
- A tenant asks "can I train my own model?"
