---
name: Per-Company Classifier Configuration
description: Company-scoped invoice classifier settings with env-var fallback, enabling per-company ML models while preserving local dev simplicity.
tags: [classifier, services, settings, multi-tenant]
author: emil
date: 2026-04-23
status: Accepted
---

# 0049. Per-Company Classifier Configuration

Date: 2026-04-23

## Status

Accepted

## Context

KSeF Hub runs three sidecar services: pdf-renderer, invoice-extractor, and invoice-classifier. All were configured via environment variables, identical for every company.

Two problems:

1. **Per-company ML models** — different companies may need different classifier endpoints (dedicated models trained on their data). A global URL can't support this.
2. **Local dev with remote DB** — if config lived only in the database, developers connecting to a shared DB (e.g., Supabase) would get production sidecar URLs instead of localhost, breaking local development.

PDF renderer and invoice extractor are shared infrastructure that rarely changes — only the classifier needs per-company configuration.

## Decision

### Env vars remain the default

All sidecar URLs and tokens stay in `runtime.exs` as environment variables. This preserves local dev: `PDF_RENDERER_URL=http://localhost:3001` just works regardless of which database you connect to.

### Classifier gets per-company DB overrides

A new `classifier_configs` table stores optional per-company overrides:

| Column | Type | Purpose |
|--------|------|---------|
| `company_id` | FK, unique | One config per company |
| `enabled` | boolean (default false) | When false, env vars are used |
| `url` | string | Classifier endpoint URL |
| `api_token_encrypted` | binary | AES-256-GCM encrypted bearer token |
| `category_confidence_threshold` | float | Auto-apply threshold |
| `tag_confidence_threshold` | float | Auto-apply threshold |

When `enabled = true`, the company's DB values override env vars for that company's classification operations. When `enabled = false` (default), env vars drive everything — the DB row is inert.

### UI in Settings → Services

Owner/admin-only settings page at `/c/:company_id/settings/services` with:
- Enable/disable toggle with fieldset that grays out when disabled
- Env var values shown as placeholders so users know what they're overriding
- Health check before save (warns if unreachable, allows save anyway)
- Collapsible API endpoint documentation

### What was considered and rejected

- **Generic service_configurations table** — started here, but only the classifier varies per company. A generic table added complexity (service_name column, settings JSON map, generic card loop) for no real benefit.
- **DB-only config (no env vars)** — broke local development when connecting to a remote database. Env vars as the baseline solved this cleanly.
- **Global (non-company-scoped) config** — one company changing the classifier URL would affect all companies. Unacceptable for a multi-tenant SaaS.

## Consequences

- Classifier client modules still read `Application.get_env` directly. Wiring per-company resolution into the classification pipeline is a separate task (the `resolve_*` functions and client behaviour changes needed).
- PDF renderer and invoice extractor have no UI — they use env vars exclusively. If per-company needs arise later, the pattern is established.
- Three migration files exist from the iteration (create generic table → update → replace with classifier-specific). Harmless on fresh DBs but noisy.

## Key Files

| File | Purpose |
|------|---------|
| `lib/ksef_hub/service_config.ex` | Context — CRUD, env_defaults |
| `lib/ksef_hub/service_config/classifier_config.ex` | Ecto schema with conditional validation |
| `lib/ksef_hub_web/live/settings_live/services.ex` | LiveView — settings page |
| `priv/repo/migrations/*classifier_configs.exs` | DB migration |
