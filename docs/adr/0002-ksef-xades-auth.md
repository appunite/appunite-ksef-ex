# 0002. KSeF Authentication via XADES Signing with xmlsec1

Date: 2026-02-07

## Status

Accepted

## Context

KSeF requires XADES-signed challenge-response authentication using PKCS12 certificates. The authentication flow is:

1. Request a challenge from KSeF (`getChallenge`)
2. Build an `AuthTokenRequest` XML embedding the challenge and NIP
3. Sign the XML with a XADES envelope signature using the taxpayer's PKCS12 certificate
4. Submit the signed XML to KSeF (`authenticateXades`)
5. Poll for completion (KSeF processes asynchronously)
6. Redeem tokens — receiving an access token (1-hour TTL) and refresh token (48-day TTL)

We need to handle certificate storage securely, perform XADES signing, and manage the token lifecycle (auto-refreshing access tokens, persisting refresh tokens across restarts).

## Decision

### XADES Signing: xmlsec1 CLI

We use `xmlsec1` via `System.cmd/3` (`KsefHub.XadesSigner.Xmlsec1`) for XADES envelope signing. There is no mature pure-Elixir or pure-Erlang XADES library. The xmlsec1 CLI is well-tested and widely used.

Secure temp file protocol:
- Write certificate and password to temp files with random names (`ksef_#{random}_#{suffix}`) and `0o600` permissions
- Pass certificate password via `--pwd-file` flag (never as a CLI argument, which would be visible in `ps`)
- Apply 30-second timeout on `System.cmd` calls
- After use: overwrite temp files with zeros (`binary.copy(<<0>>, size)`) then delete

### Secret Encryption: AES-256-GCM

Certificate data and refresh tokens are encrypted at rest using AES-256-GCM (`KsefHub.Credentials.Encryption`):
- 12-byte random IV, 16-byte authentication tag
- Additional Authenticated Data (AAD) set to module name
- Stored as concatenated binary: `iv <> tag <> ciphertext`
- Encryption key sourced from GCP Secret Manager in production; derived from `SECRET_KEY_BASE` in development

### Token Lifecycle: GenServer

`KsefHub.KsefClient.TokenManager` is a singleton GenServer managing the access/refresh token pair:
- Stores current tokens and expiry times in process state
- `ensure_access_token/0` checks validity and auto-refreshes 2 minutes before expiry (`@refresh_buffer_seconds = 120`)
- Persists encrypted refresh token to the database for restart recovery (`init/1` loads from DB)
- Returns `{:error, :reauth_required}` when both tokens expire, triggering full XADES re-authentication

### Auth Orchestration

`KsefHub.KsefClient.Auth.authenticate/3` orchestrates the full flow using a `with` pipeline:
1. Get challenge → 2. Sign with xmlsec1 → 3. Submit to KSeF → 4. Poll every 2 seconds (max 30 attempts / 60 seconds) → 5. Redeem tokens → 6. Store in TokenManager

### Testability

Both `KsefHub.KsefClient.Behaviour` and `KsefHub.XadesSigner.Behaviour` are accessed via `Application.get_env` with Mox mocks in tests. No xmlsec1 or KSeF API calls in the test suite.

Alternatives considered:

- **Pure Elixir XML signing**: No mature library exists for XADES envelope signatures with PKCS12 certificates
- **Java bridge (e.g., via JInterface)**: Would handle XADES natively but adds JVM dependency and operational complexity
- **Store tokens only in DB (no GenServer)**: Loses auto-refresh capability; every API call would need a DB round-trip to check token validity

## Consequences

- **System dependency**: `xmlsec1` must be installed in the Docker image (`apt-get install xmlsec1`)
- **Secure temp file discipline**: Every code path writing secrets to disk must follow the zero-overwrite-delete protocol
- **GCP Secret Manager coupling**: Production encryption key management depends on GCP; could be swapped via the config layer
- **48-day re-auth cycle**: When the refresh token expires, full XADES authentication is required — the system handles this automatically but it involves certificate decryption and xmlsec1 invocation
- **Single active session per NIP**: KSeF enforces one session at a time; TokenManager's singleton design aligns with this constraint
