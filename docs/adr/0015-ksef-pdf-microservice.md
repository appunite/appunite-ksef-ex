# 0015. KSeF PDF Microservice

Date: 2026-02-12

## Status

Accepted

## Context

The previous PDF generation pipeline (ADR 0004) used a two-stage approach: xsltproc (XML→HTML via gov.pl XSL stylesheets) + Gotenberg/Chromium (HTML→PDF). While functional, this had several drawbacks:

1. **Output quality** — The generated PDFs didn't match the official government portal rendering
2. **System dependencies** — Required bundling xsltproc and maintaining gov.pl XSL stylesheets locally
3. **Complexity** — Two-stage pipeline with fallback template for environments without xsltproc
4. **Maintenance burden** — `scripts/update-ksef-stylesheet.sh` needed to track gov.pl schema changes

The official open-source KSeF PDF generator ([CIRFMF/ksef-pdf-generator](https://github.com/CIRFMF/ksef-pdf-generator)) produces output matching the government portal. Our fork ([appunite/ksef-pdf-generator](https://github.com/appunite/ksef-pdf-generator)) wraps it with an HTTP server providing both PDF and HTML generation endpoints.

## Decision

Replace the xsltproc + Gotenberg pipeline with a single **ksef-pdf microservice** sidecar (`ghcr.io/appunite/ksef-pdf:latest`).

The microservice exposes:
- `POST /generate/pdf` — XML → PDF (application/pdf)
- `POST /generate/html` — XML → HTML (text/html)
- `GET /health` — Health check

Optional headers: `X-KSeF-Number`, `X-KSeF-QRCode`

Key changes:
- `Pdf.Behaviour` callback `generate_pdf/2` now accepts `(xml_content, metadata)` instead of `(html)`
- Single `KsefPdfService` module replaces `Xsltproc`, `Gotenberg`, and `FallbackTemplate`
- Callers collapse the two-step `generate_html → generate_pdf` into a single `generate_pdf` call
- No xsltproc or XSL stylesheets needed in the application container
- Config key changes from `GOTENBERG_URL` to `KSEF_PDF_URL`

## Consequences

- **Better output quality** — PDFs match the official government portal
- **Simpler pipeline** — One HTTP call per operation instead of xsltproc + Gotenberg chain
- **Fewer system dependencies** — No xsltproc in the Docker image, no bundled XSL files
- **No fallback template** — The service handles all HTML rendering; no degraded mode needed
- **Different sidecar** — Gotenberg replaced by ksef-pdf (port 3001 instead of 3000)
- **Breaking change** — `generate_pdf/2` signature changed; callers must update
