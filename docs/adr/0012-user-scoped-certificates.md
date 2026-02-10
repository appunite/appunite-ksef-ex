# 0012. User-Scoped KSeF Certificates

Date: 2026-02-10

## Status

Accepted

Supersedes the implicit credential-per-company certificate model from [ADR 0008](0008-multi-company-support.md).

## Context

KSeF person certificates are tied to the individual (identified by PESEL), not to any company. One certificate authenticates for all companies where the person has KSeF authorization — the NIP in the `getChallenge` request determines the company context, not the certificate itself (see [docs/ksef-certificates.md](../ksef-certificates.md) for full details).

The current model stores certificate data (`certificate_data_encrypted`, `certificate_password_encrypted`) on `ksef_credentials`, which is company-scoped. This forces users to re-upload the same certificate file for each company — redundant, confusing, and incorrect in its modeling of the domain.

## Decision

Create a new `user_certificates` table to store certificate data at the user level:

```text
user_certificates
├── id
├── user_id              (FK → users)
├── certificate_data_encrypted
├── certificate_password_encrypted
├── subject              (parsed from cert: name, PESEL/NIP)
├── not_before           (certificate validity start)
├── not_after            (certificate validity end)
├── fingerprint          (SHA-256 of DER, for dedup/display)
└── inserted_at / updated_at
```

Strip certificate data columns from `ksef_credentials`. That table becomes company sync configuration only:

```text
ksef_credentials (after migration)
├── id
├── company_id
├── nip
├── is_active
├── last_sync_at
├── token_manager fields...
└── inserted_at / updated_at
```

**Sync worker flow change:** The sync worker loads the company's `ksef_credentials` for the NIP and sync state, then finds the owner's certificate by joining through `memberships` (role = `owner`) to `user_certificates`. The certificate is used to sign the challenge for the company's NIP.

**Certificate upload** becomes a user-level action, accessible from user settings rather than per-company certificate pages.

## Consequences

- One certificate upload serves all of a user's companies — no more duplicate uploads.
- `ksef_credentials` becomes a lighter table focused on sync configuration.
- The sync worker must join through `memberships` to find the appropriate certificate, adding a dependency on the RBAC model from [ADR 0011](0011-per-company-rbac.md).
- If a company owner has no certificate uploaded, sync cannot run — the UI should surface this clearly.
- Certificate expiry tracking moves to the user level; notifications about expiring certificates are sent to the user, not per-company.
