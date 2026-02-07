# 0005. PostgreSQL on Supabase

Date: 2026-02-07

## Status

Accepted

## Context

KSeF Hub needs a relational database for invoices, credentials, sync checkpoints, API tokens, and user accounts. Requirements:

1. Strong transactional guarantees — upserts with unique constraints for invoice deduplication, atomic credential updates
2. Rich querying — composite filters (type + status + date range + NIP + text search) on the invoices table
3. Ecto compatibility — Phoenix/Ecto is the ORM, so PostgreSQL is the natural fit
4. Managed hosting — the team is small; self-managing a database adds operational burden
5. Row-Level Security is not needed — the app has a single tenant model (one NIP per deployment)

## Decision

We use **PostgreSQL** hosted on **Supabase** in production, accessed via standard `Ecto.Adapters.Postgres` with a `DATABASE_URL` connection string.

Key design choices:

- **No Supabase-specific features**: The application uses standard PostgreSQL via Ecto. No Supabase client libraries, Realtime subscriptions, or Row-Level Security policies. This keeps the app portable — switching to any PostgreSQL host (RDS, Cloud SQL, self-hosted) requires only changing `DATABASE_URL`.
- **Binary UUIDs as primary keys**: All tables use `{:id, :binary_id, autogenerate: true}` for globally unique identifiers without coordination.
- **Upsert patterns**: Invoice sync relies on `Repo.insert(changeset, on_conflict: {:replace, [...]}, conflict_target: :ksef_number)` for idempotent deduplication.
- **Oban jobs table**: Oban manages its own `oban_jobs` table in the same database for durable job scheduling.
- **Connection pooling**: Default pool size of 10, configurable via `POOL_SIZE` env var. IPv6 support via `ECTO_IPV6` for Supabase's IPv6 endpoints.

Alternatives considered:

- **Self-hosted PostgreSQL**: Full control but adds operational burden (backups, monitoring, upgrades) for a small team.
- **GCP Cloud SQL**: Natural fit for Cloud Run deployment, but Supabase offers a more generous free tier and built-in dashboard for quick inspection.
- **SQLite (via Ecto SQLite3)**: Simpler deployment but lacks concurrent write support needed for Oban workers running alongside web requests.

## Consequences

- **Vendor-neutral persistence layer**: The only Supabase-specific detail is the connection string format. Migration to any PostgreSQL host is trivial.
- **Standard Ecto migrations**: All schema changes go through `priv/repo/migrations/`, versioned and reproducible.
- **Network latency**: Supabase-hosted PostgreSQL adds network hops compared to a co-located database. Acceptable for the current request volume; connection pooling mitigates overhead.
- **Free tier limits**: Supabase free tier has connection and storage limits. Production deployment will need the Pro plan as invoice volume grows.
- **SSL in production**: Supabase connections should use SSL (`ssl: true` in Repo config) for data in transit encryption.
