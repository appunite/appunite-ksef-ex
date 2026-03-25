# 0036. Transition from Payroll to KSeF Hub for Invoice Management

Date: 2026-03-24

## Status

Accepted

# Context

KSeF (Krajowy System e-Faktur) becomes obligatory on 1 April 2026. Every invoice issued by a Polish entity will go through KSeF. This is a big change for us — but also a big opportunity.

The initial idea was to bolt a KSeF module onto our existing payroll.appunite.com service. But after looking at the scope, I realized we could do much better by building a new dedicated service from scratch. Over the past few weeks of after-hours work, I've built **invoices.appunite.com** — a complete, standalone service that replaces the invoice-related parts of Payroll and adds capabilities we never had before.

The service spans multiple domains and technologies:

- **Core service** (Elixir/Phoenix + PostgreSQL) — KSeF integration (certificate auth, XADES signing, automated sync), invoice management with approval workflows, team RBAC, REST API with OpenAPI docs
- **PDF invoice decoding** (OCR + LLM) — standalone open-source service ([au-ksef-unstructured](https://github.com/appunite/au-ksef-unstructured)) replacing Google Document AI
- **KSeF PDF renderer** — standalone open-source service ([ksef-pdf-generator](https://github.com/appunite/ksef-pdf-generator)) rendering FA(3) XML into PDF/HTML
- **Invoice category prediction** (ML) — standalone open-source service ([au-payroll-model-categories](https://github.com/appunite/au-payroll-model-categories)) auto-classifying expenses, trained on our historical data
- **Email forwarding** — dedicated inbound email for People Team to collect PDF invoices by simply forwarding from their mailbox

# What problems do we aim to solve

- **Reliable invoice collection and categorization** — KSeF is obligatory from 1 April 2026, so we need a system that integrates with it to reliably download and categorize invoices. Expense categorization is critical for our expense tracking and analytics — it's the foundation of how we understand company spending. During the adaptation window, we also need deduplication patterns to handle invoices coming from both KSeF and other sources (e.g., email, manual upload).
- **Cost reduction** — the legacy system uses Google Document AI for extracting data from PDF invoices, which is costly. We can do better by building our own extraction pipeline.
- **Reliability and ease of use** — the current process has too much friction. We need something that just works — for the People Team collecting invoices and for Appunite members submitting them.
- **Accountant as part of the system** — today, synchronizing invoice data with our accountant is too manual. The accountant should be able to log in, download invoices, see how we categorize expenses, how we tag them, and share notes and comments — all in one place.
- **Use our core technology** — the legacy codebase's technology choices make it harder for team members to contribute. The new service is built with Elixir/Phoenix — technology that is core to Appunite.
- **Revenue invoices (bonus)** — with KSeF mandatory, every invoice issuer (InFakt included) must sync invoices to KSeF. We can pull income invoices directly from KSeF instead of the InFakt API — making us invoice-issuer agnostic. We could switch away from InFakt tomorrow and nothing would break.

# Hypothesis

By building a bespoke solution strictly adapted to our processes, we can:

- **Adapt to changing regulations** — a system we fully own and understand lets us react quickly to government and legal changes (like KSeF itself), rather than being constrained by third-party tools or a rigid legacy codebase.
- **Clean up expense collection and analysis** — replacing the fragmented legacy process with a single, purpose-built system will bring clarity to how we collect, categorize, and analyze expenses.
- **Improve cooperation with the accountant** — giving the accountant direct access to invoices, categories, tags, and notes makes the handoff seamless instead of manual.
- **Make adding invoices faster and easier** — automated KSeF sync, email forwarding with OCR/LLM extraction, and pre-filled forms mean less manual work for the People Team.
- **Improve expense analysis** — structured categorization and tagging will make expense analysis easier and more reliable than the current process.
- **Open the door for income invoice management** — the system already supports income invoice collection via KSeF. When we're ready, we can switch from the InFakt API to our own system — the functionality is built and waiting for the decision.

Success criteria:
- All invoices from April 2026 onward are collected exclusively through KSeF Hub
- Non-KSeF invoices are successfully processed via email or manual upload
- The People Team can fully manage invoice collection without the legacy system
- No data gaps during the transition period
- Analytics continuity via BigQuery UNION of legacy and new tables

# Implementation plan

1. **Set up Airbyte/BigQuery sync** — the only remaining technical work. The issue-date-based cutover enables a clean UNION of legacy and new tables for one continuous invoice collection in BigQuery — no gaps, no overlaps.
2. **Prepare knowledge base documentation** — write articles covering:
   - How the People Team collects and processes invoices in KSeF Hub
   - What employees need to do when they have a PDF invoice to submit
   - How KSeF invoices are synced automatically and what requires manual action
   - How to work with the accountant through the system (tags, categories, notes)
3. **31 March 2026** — block invoices with issue date after 31 March 2026 on payroll.appunite.com. Older invoices can still be submitted to the legacy system. Historical data remains accessible in read-only mode.
4. **1 April 2026** — go live with invoices.appunite.com. All invoices with issue date from 1 April 2026 onward are collected in the new system. Only People Team members have access.

**How it works after go-live:**
- **Polish invoices (KSeF)** — automatically synced. No action needed from anyone.
- **Non-KSeF invoices (employees)** — send it to people@appunite.com. The People Team takes care of the rest.
- **Non-KSeF invoices (People Team)** — forward invoice emails to the dedicated inbound email or upload a PDF from the app. The system decodes the invoice (OCR + LLM), pre-fills the form. Review, tag/categorize, add notes for the accountant, or create a payment request.
