# Architecture Guide

Quick reference for developers. Before touching a feature area:

1. Find it in **Feature → Files Map** to know which files to read
2. Check **Behavioral Contracts** for non-obvious invariants that affect your change
3. Read the relevant ADR(s) from the **ADR Index** for the decision rationale

---

## Feature → Files Map

| Feature | Key files |
|---------|-----------|
| Invoice export (ZIP + CSV) | `lib/ksef_hub/exports.ex`, `exports/csv_builder.ex`, `exports/export_batch.ex`, `live/export_live/index.ex` |
| KSeF sync | `lib/ksef_hub/sync/sync_worker.ex`, `sync/invoice_fetcher.ex`, `ksef_client/` |
| FA(3) XML parsing | `invoices/parser.ex`, `docs/fa3-xml.md` (field mapping reference) |
| Invoice CRUD & business logic | `lib/ksef_hub/invoices.ex` (facade) + `invoices/` sub-modules |
| Public invoice sharing (token links) | `invoices/public_tokens.ex`, `invoices/invoice_public_token.ex`, `live/invoice_live/public_show.ex` |
| Invoice approval & auto-approval | `invoices.ex` (`approve_invoice`), `invoices/auto_approval.ex` |
| Invoice categories & ML classification | `invoices/category.ex`, `invoice_classifier/` |
| PDF generation | `pdf_renderer.ex`, `pdf_renderer/client.ex` |
| PDF extraction (expense uploads) | `invoice_extractor/` |
| Inbound email invoices | `inbound_email/` |
| Activity log | `activity_log/tracked_repo.ex`, `activity_log/events.ex` |
| RBAC / permissions | `authorization.ex` |
| Invoice access control | `invoices/access_control.ex` |
| API tokens | `accounts/api_tokens.ex` |
| Payment CSV export | `payment_requests/` |

---

## Behavioral Contracts

Non-obvious invariants that affect multiple features. Violating these is usually a bug.

| Invariant | Source |
|-----------|--------|
| Income invoices always have `expense_approval_status: :pending` — there is no approval workflow for them | ADR-0007 |
| Categories are **expense-only** — `set_invoice_category` rejects income invoices with `{:error, :expense_only}` | ADR-0032 |
| KSeF source invoices (`:ksef`) are never auto-approved, even expenses — auto-approval is for `:manual`, `:pdf_upload`, `:email` sources only | ADR-0041 |
| KSeF invoice **data fields** are immutable — only metadata (category, tags, cost line, note, billing dates) is editable after sync | ADR-0032 (block-ksef-editing) |
| `TrackedRepo` must replace `Repo` for any write that should appear in the activity log | ADR-0042 |
| **Approver** role sees **expense invoices only** — income (always `access_restricted`) is hidden unless explicitly granted | ADR-0047 |
| **Analyst** role has the same data scope as approver — access grants are still required for restricted invoices; `view_all_invoice_types` is NOT granted | ADR-0047 |
| Public invoice tokens are stored as **SHA-256 digests only** — raw bearer tokens are never persisted; each "copy link" call rotates the token and invalidates the previous URL | ADR-0046 |
| Export CSV uses **semicolons** as delimiter (comma-delimited files don't open correctly in Polish-locale Windows Excel) | — |
| Duplicate invoices (`duplicate_of_id` is set) are excluded from exports | `exports.ex` |
| All company-scoped routes are prefixed with `/c/:company_id` | ADR-0027 |

---

## ADR Index

Read only the ADR(s) relevant to your task — the summaries below tell you which ones apply.

| File | Title | Status | Decision |
|------|-------|--------|----------|
| 0001-use-elixir-phoenix.md | Use Elixir/OTP with Phoenix | Accepted | Elixir 1.16+, Phoenix 1.8 + LiveView, Ecto, PostgreSQL, Oban |
| 0002-ksef-xades-auth.md | KSeF Authentication via XADES Signing | Accepted | xmlsec1 CLI for XADES envelope signing with secure temp files |
| 0003-incremental-sync-oban.md | Incremental Invoice Sync with Oban | Accepted | Oban cron for 15-min KSeF sync with per-type checkpoints and rate limiting |
| 0004-pdf-generation-xsltproc.md | PDF Generation via xsltproc + Gotenberg | Superseded by 0015-ksef-pdf-microservice.md | Two-stage: xsltproc (XML→HTML) + Gotenberg (HTML→PDF) |
| 0005-supabase-database.md | PostgreSQL on Supabase | Accepted | Supabase-managed Postgres with binary UUIDs, Oban jobs table |
| 0006-api-token-hashed-bearer.md | Hashed Bearer API Tokens | Accepted | SHA-256 hashed 32-byte tokens with prefix, soft-delete revocation |
| 0007-unified-invoice-api.md | Unified Invoice Model and API | Accepted | Single `invoices` table with `type` discriminator; status only meaningful for expenses |
| 0008-multi-company-support.md | Multi-Company Support | Accepted | `companies` table with per-company credentials, sync, and context switching |
| 0009-openapi-open-api-spex.md | OpenAPI with open_api_spex | Accepted | `open_api_spex` for OpenAPI 3.0 specs with SwaggerUI at `/dev/swaggerui` |
| 0010-key-crt-certificate-upload.md | Support .key + .crt Upload | Accepted | Server-side .key + .crt → .p12 conversion via `openssl pkcs12` |
| 0011-per-company-rbac.md | Per-Company RBAC | Accepted | `memberships` table with role-based permissions per company |
| 0012-user-scoped-certificates.md | User-Scoped KSeF Certificates | Accepted | `user_certificates` table storing certs at user level with metadata |
| 0013-email-password-auth.md | Email/Password Authentication | Accepted | `phx.gen.auth` email/password with optional Google Sign-In |
| 0014-company-invitation-system.md | Company Invitation System | Accepted | `invitations` table with token auth, expiry, and role assignment |
| 0015-invoice-pagination-search-indexes.md | Invoice Pagination & Search Indexes | Accepted | Offset-based pagination (25/page), BTREE indexes for filtering |
| 0015-ksef-pdf-microservice.md | KSeF PDF Microservice | Accepted | Dedicated `ksef-pdf` sidecar for PDF/HTML generation from FA(3) XML |
| 0016-reviewer-expense-only-visibility.md | Reviewer Expense-Only Visibility | Superseded by 0047 | Reviewer role scoped to expense invoices only across all access paths |
| 0017-unstructured-pdf-extraction-sidecar.md | PDF Extraction Sidecar | Accepted | `au-ksef-unstructured` sidecar for OCR + Claude-based JSON extraction |
| 0018-manual-invoice-creation.md | Manual Invoice Creation | Accepted | `POST /api/invoices` with duplicate detection via `:suspected` flag |
| 0019-ml-prediction-sidecar.md | ML Prediction Sidecar | Accepted | `au-payroll-model-categories` sidecar for category/tag auto-classification |
| 0020-pdf-invoice-upload-flow.md | PDF Invoice Upload Flow | Accepted | `:pdf_upload` source with `extraction_status` tracking and PDF storage |
| 0021-future-invoice-documents-table.md | Future Invoice Documents Table | Superseded by 0026-generic-files-table.md | Extract xml/pdf content to a separate `invoice_documents` table |
| 0023-ecto-enum-for-string-enums.md | Ecto.Enum for String Enums | Accepted | Replace bare string enums with `Ecto.Enum` atoms for type safety |
| 0024-tech-debt-invoice-creation-and-client-tests.md | Tech Debt: Invoice Creation Pattern | Implemented | Deduplicate create-then-retry-as-duplicate pattern across context functions |
| 0025-inbound-email-invoice-processing.md | Inbound Email Invoice Processing | Accepted | Mailgun inbound routes for per-company email-to-invoice with extraction |
| 0026-generic-files-table.md | Generic Files Table | Implemented | Generic `files` table with FK columns used by invoices, inbound emails |
| 0027-company-scoped-urls.md | Company-Scoped URLs | Accepted | All routes prefixed with `/c/:company_id`; enables direct-link sharing |
| 0028-classifier-sidecar-gcs-models.md | Classifier Sidecar with GCS Models | Accepted | Classifier as Cloud Run sidecar with GCS-mounted ML model weights |
| 0029-centralized-authorization-and-role-refactor.md | Centralized Authorization | Accepted | `KsefHub.Authorization` with a single `can?/2` permission matrix |
| 0030-public-shareable-invoice-urls.md | Public Shareable Invoice URLs | Superseded by 0046 | `public_token` column with unauthenticated `/public/invoices/:token` endpoint |
| 0031-track-invoice-creator.md | Track Invoice Creator | Accepted | `created_by_id` FK with creator display on detail page |
| 0032-block-ksef-invoice-data-editing.md | Block KSeF Invoice Data Editing | Accepted | KSeF source invoice data fields immutable; only metadata editable |
| 0032-expense-categories-typed-tags.md | Expense Categories & Typed Tags | Accepted | Categories restricted to expenses; tags have `:expense`/`:income` type |
| 0033-billing-date-field.md | Billing Date Field | Superseded by 0034-billing-date-range.md | Single `billing_date` for accounting period assignment |
| 0034-billing-date-range.md | Billing Date Range | Accepted | `billing_date_from`/`billing_date_to` for multi-month cost allocation |
| 0034-invoice-exclusion.md | Invoice Exclusion | Accepted | `is_excluded` boolean to hide invoices from reports without deleting |
| 0035-invoice-access-control.md | Invoice Access Control | Accepted | `access_restricted` flag with `invoice_access_grants` join table |
| 0036-transition-to-ksef-hub.md | Transition to KSeF Hub | Accepted | New dedicated KSeF Hub service replacing payroll invoice functionality |
| 0037-cost-line.md | Cost Line | Accepted | `cost_line` enum field for expense attribution to business cost centers |
| 0038-project-tag.md | Project Tag | Accepted | `project_tag` string field for lightweight free-form project attribution |
| 0039-company-bank-accounts.md | Company Bank Accounts | Accepted | `company_bank_accounts` table with currency/IBAN for payment CSV export |
| 0040-simplify-tags-to-string-array.md | Simplify Tags to String Array | Accepted | Replace tag entity with `tags string[]` column; ML model writes directly |
| 0041-auto-approve-trusted-invoices.md | Auto-Approve Trusted Invoice Sources | Accepted | Per-company opt-in flag; approves `:manual`, `:pdf_upload`, `:email` expenses only |
| 0042-activity-log.md | Activity Log System | Accepted | `Trackable` behaviour on schemas + `TrackedRepo` for automatic audit events |
| 0043-component-driven-ui.md | Component-Driven UI | Accepted | Extract shared UI patterns (3+ occurrences) to `CoreComponents` |
| 0044-correction-invoice-support.md | Correction Invoice Support | Accepted | `invoice_kind` enum (VAT/KOR/ZAL) with FK to corrected original |
| 0045-rename-expense-invoice-columns.md | Rename Expense-Specific Invoice Columns | Accepted | 11 expense-only columns prefixed with `expense_`/`prediction_expense_`; breaking API change |
| 0046-per-user-public-invoice-tokens.md | Per-User Public Invoice Tokens | Accepted | Per-(invoice, user) tokens in `invoice_public_tokens` table; only SHA-256 digest stored; 30-day TTL; revoked on member block |
| 0047-approver-analyst-roles.md | Approver and Analyst Roles | Accepted | Rename `:reviewer` → `:approver` and `:viewer` → `:analyst`; analyst has same data scope as approver (access grants required for restricted invoices) |
