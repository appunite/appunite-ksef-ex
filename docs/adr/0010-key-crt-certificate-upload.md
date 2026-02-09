# 0010. Support .key + .crt Certificate Upload

Date: 2026-02-09

## Status

Accepted

## Context

Users downloading certificates from the KSeF Gov portal receive separate `.key` and `.crt` files rather than a single `.p12` (PKCS12) bundle. Converting these to `.p12` requires running `openssl pkcs12 -export` in the terminal — a step inaccessible to non-technical users such as accountants.

Our existing upload form only accepts `.p12` / `.pfx` files, forcing all users through the manual conversion step.

## Decision

Add a server-side `.key + .crt` to `.p12` conversion flow:

1. **Toggle in upload form** — users choose between `.p12` mode (existing) and `.key + .crt` mode (new).
2. **Server-side conversion** — call `openssl pkcs12 -export` via `System.cmd` to produce an in-memory `.p12` bundle with a generated random password.
3. **Behaviour + DI** — define `KsefHub.Credentials.Pkcs12Converter.Behaviour` so tests can mock the conversion. Production uses `Pkcs12Converter.Openssl`.
4. **Secure temp files** — reuse the `KsefHub.SecureTemp` module (extracted from `XadesSigner.Xmlsec1`) for writing key/cert/password to temp files with `0600` permissions, cleaned up after use.
5. **After conversion** — the resulting `.p12` binary and generated password flow into the existing `save_credential/3` path (encrypt + store).

## Consequences

- **New system dependency:** `openssl` CLI must be available in the Docker image (already present in our base image).
- **No schema changes:** the database still stores encrypted PKCS12 data; conversion happens before persistence.
- **UX improvement:** accountants can upload certificates directly from the Gov portal without terminal commands.
- **Security:** private keys are written to temp files with `0600` permissions, overwritten with zeros, then deleted — same pattern as xmlsec1 signing.
