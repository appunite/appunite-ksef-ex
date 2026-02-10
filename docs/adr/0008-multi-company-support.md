# 0008. Multi-Company Support

Date: 2026-02-08

## Status

Accepted — access model superseded by [ADR 0011](0011-per-company-rbac.md) (per-company RBAC), certificate model superseded by [ADR 0012](0012-user-scoped-certificates.md) (user-scoped certificates)

## Context

KSeF Hub was originally single-tenant — one active credential (NIP), all invoices in one pool, no company concept. Users need to manage multiple companies, each with its own NIP, certificate, and invoices. Switching context between companies should filter the entire UI and API to that company's data.

## Decision

Introduce a `companies` table as the central ownership entity. Every credential, invoice, and sync checkpoint gains a `company_id` foreign key. A company is created first (with NIP), then a certificate is uploaded for it.

**Key design choices:**

1. **All authenticated users see all companies** — no per-user RBAC. The email allowlist is the sole access gate.
2. **Company context switching** — session stores `current_company_id`; LiveAuth loads it into socket assigns. API controllers accept `company_id` as a query parameter.
3. **TokenManager becomes per-company** — replace singleton GenServer with Registry-based dynamic instances keyed by `company_id`.
4. **SyncDispatcher replaces direct cron** — an Oban cron job dispatches one `SyncWorker` per company with an active credential, enabling parallel per-company syncs.
5. **No backward compatibility required** — existing API contracts change freely (adding required `company_id` param).

## Consequences

- Every context function gains a `company_id` parameter, enforcing data isolation at the query level.
- The `companies` table uses `on_delete: :restrict` to prevent accidental deletion of companies with linked data.
- Credential NIP is auto-populated from the company's NIP, removing user input of NIP during certificate upload.
- PubSub topics become company-scoped (`sync:status:#{company_id}`) for targeted UI updates.
- New users with no companies are redirected to create one before accessing the dashboard.
