# 0004. PDF Generation via xsltproc + Gotenberg

Date: 2026-02-07

## Status

Superseded by 0015

## Context

KSeF Hub needs to generate human-readable PDF invoices from FA(3) XML. The Polish government provides XSL stylesheets for visualizing FA(3) invoices. We need a pipeline that:

1. Transforms XML to HTML using the official gov.pl XSL stylesheet
2. Converts HTML to PDF for download
3. Works reliably in Docker/Cloud Run without browser dependencies
4. Degrades gracefully when system dependencies are unavailable

## Decision

We use a two-stage pipeline:

1. **xsltproc** (XML → HTML): The standard XSLT 1.0 processor, available via `apt-get install xsltproc`. We bundle the gov.pl stylesheets locally in `priv/xsl/` with patched import paths (no network access during transformation via `--nonet`).

2. **Gotenberg** (HTML → PDF): A Docker-based service wrapping Chromium for HTML-to-PDF conversion. Runs as a sidecar container, accessed via HTTP multipart POST.

3. **Fallback template**: When xsltproc is unavailable (development, CI without system deps), `FallbackTemplate` uses the existing `Invoices.Parser` to extract structured data and renders a basic HTML template directly in Elixir.

Key design choices:
- Secure temp files with 0600 permissions for xsltproc input (same pattern as XADES signing)
- 30-second timeout on xsltproc commands
- Temp files zeroed before deletion
- Gotenberg accessed via `Req` HTTP client (already a dependency)
- `Pdf.Behaviour` allows mocking in tests

## Consequences

- **System dependencies**: xsltproc and Gotenberg must be available in production Docker image
- **Graceful degradation**: HTML preview works without Gotenberg; fallback template works without xsltproc
- **Stylesheet maintenance**: `scripts/update-ksef-stylesheet.sh` fetches and patches gov.pl stylesheets when schema version changes
- **No browser dependency in app container**: Chromium runs in the Gotenberg sidecar only
- **Testing**: Unit tests use the fallback path; integration tests (tagged `@tag :integration`) require xsltproc and/or Gotenberg
