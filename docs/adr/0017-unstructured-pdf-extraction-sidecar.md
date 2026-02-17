# 0017. Unstructured PDF Invoice Extraction Sidecar

Date: 2026-02-17

## Status

Accepted

## Context

KSeF Hub currently handles only structured FA(3) XML invoices fetched directly from the KSeF API. However, users will need to upload arbitrary invoice PDFs (scans, exports from other systems, foreign invoices) that don't originate from KSeF and have no structured XML representation.

To store these invoices we need to extract structured data (seller/buyer NIP, invoice number, dates, amounts, line items, etc.) from unstructured PDF content. This is a fundamentally different capability from what the Elixir application provides — it requires PDF text extraction (OCR, table detection) and LLM-based structured output.

We built a dedicated Python microservice ([au-ksef-unstructured](https://github.com/emilwojtaszek/au-ksef-unstructured)) for this purpose. Its pipeline is:

```
PDF → unstructured (text extraction + OCR) → Anthropic Claude (structured output) → JSON
```

The service uses `unstructured[pdf]` for text/table extraction (with poppler, tesseract OCR) and Anthropic Claude's structured output feature to map extracted text to a well-defined JSON schema. By default it extracts Polish KSeF invoice fields, but it also accepts a custom JSON Schema for arbitrary extraction.

This follows the same sidecar pattern we already use for PDF rendering (ADR 0015 — ksef-pdf microservice).

## Decision

Run **au-ksef-unstructured** as a sidecar microservice alongside KSeF Hub, the same way we run ksef-pdf.

- **Image:** built from `github.com/emilwojtaszek/au-ksef-unstructured` Dockerfile
- **Port:** 3002
- **API:** `POST /extract` — accepts a PDF file, returns structured invoice JSON
- **Auth:** Bearer token shared between KSeF Hub and the sidecar via `UNSTRUCTURED_API_TOKEN` env var
- **Config:** `UNSTRUCTURED_URL` env var in KSeF Hub (e.g., `http://localhost:3002`)

Integration in the Elixir app:
- New `KsefHub.Unstructured` context with a behaviour (`KsefHub.Unstructured.Behaviour`) for testability via Mox
- The behaviour defines a `extract/2` callback that accepts PDF binary and optional schema override
- Production implementation (`KsefHub.Unstructured.Client`) makes an HTTP multipart POST to the sidecar
- The upload flow will be: receive PDF → call sidecar for extraction → validate/review extracted data → persist invoice

## Consequences

- **Enables PDF invoice uploads** — users can upload any invoice PDF, not just KSeF-sourced XML
- **Consistent sidecar pattern** — follows the same architecture as ksef-pdf (ADR 0015), keeping the Elixir app focused on business logic
- **Language-appropriate tooling** — PDF parsing and LLM integration are well-served by the Python ecosystem (unstructured, anthropic SDK)
- **Independent scaling** — the extraction service can be scaled separately since it is CPU/GPU-intensive (OCR) and has longer request times
- **Additional infrastructure** — one more container to deploy, monitor, and maintain
- **LLM cost** — each extraction incurs an Anthropic API call; cost scales with upload volume
- **New env vars** — `UNSTRUCTURED_URL` and `UNSTRUCTURED_API_TOKEN` required in production
