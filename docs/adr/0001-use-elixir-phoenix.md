# 0001. Use Elixir/OTP with Phoenix

Date: 2026-02-07

## Status

Accepted

## Context

KSeF Hub is a dedicated service for Poland's National e-Invoice System that needs to:

1. Run concurrent background sync jobs polling KSeF every 15 minutes, with rate-limited API calls (8 req/s download, 2 req/s query)
2. Manage long-lived processes — a `TokenManager` GenServer holding access/refresh tokens with auto-refresh, and an Oban-backed job queue surviving restarts
3. Serve both a LiveView admin UI (real-time sync status, invoice browsing) and REST JSON APIs for consumer applications from a single deployable
4. Handle fault tolerance gracefully — if a sync job crashes, it should retry without taking down the rest of the system

We evaluated several technology stacks for these requirements.

## Decision

We use **Elixir 1.16+ / OTP 26+** with **Phoenix 1.8+** as the primary framework:

- **Phoenix LiveView 1.1** for the admin UI — real-time updates via PubSub when sync completes, no separate frontend build
- **Ecto 3.13** with **PostgreSQL** (Supabase-hosted) for persistence
- **Oban 2.18** for durable background job scheduling (cron-based sync worker)
- **Tailwind CSS + DaisyUI** for UI styling — ships with Phoenix, no custom design system needed
- **Req** as HTTP client for KSeF API communication
- **Mox** for behaviour-based test mocking

Alternatives considered:

- **Node.js / Express**: Good ecosystem, but lacks OTP supervision trees for managing GenServer token lifecycle and fault-tolerant background processing. Would require Redis + Bull for job queues that OTP provides natively.
- **Python / Django**: Strong ORM and admin UI, but concurrency model (asyncio or Celery workers) adds operational complexity compared to BEAM processes. No LiveView equivalent without a separate frontend.
- **Go**: Excellent concurrency via goroutines, but no equivalent to OTP supervisors for process lifecycle management. Would need a separate frontend framework and job queue infrastructure.

## Consequences

- **Smaller hiring pool**: Elixir developers are less common than Node.js or Python developers, which may affect team scaling
- **Steeper learning curve**: OTP concepts (GenServer, supervision trees, behaviours) require ramp-up time
- **Single deployable**: One Docker image serves REST API, LiveView admin UI, and background sync — simpler infrastructure than a multi-service setup
- **Fault tolerance built in**: OTP supervisors restart crashed processes automatically; Oban retries failed jobs with backoff
- **Behaviour-based DI**: All external dependencies (KSeF API, XADES signer, PDF generator) accessed through behaviours, enabling Mox-based testing with `async: true`
- **Real-time UI for free**: PubSub broadcasts from sync workers update LiveView pages without WebSocket plumbing or a JavaScript framework
