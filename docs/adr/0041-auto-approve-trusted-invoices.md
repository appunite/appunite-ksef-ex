# 0041. Auto-Approve Trusted Invoice Sources

Date: 2026-04-05

## Status

Accepted

## Context

All invoices currently default to `status: :pending` regardless of how they enter the system. Users must manually approve every expense invoice, including ones they uploaded themselves or sent via email from their own account. This creates unnecessary friction for trusted sources.

However, some invoices genuinely need human verification:
- **KSeF invoices** arrive from an external system and may not belong to the company
- **Email invoices from unknown senders** (people without a KSeF Hub platform account or not a member of the company) need review
- **Invoices with incomplete extraction** (`:partial` or `:failed`) lack the data needed to confirm correctness

Different companies may have different policies — some want every invoice reviewed regardless of source. The feature must be opt-in.

## Decision

Add a per-company boolean setting `auto_approve_trusted_invoices` (default: `false`). When enabled, expense invoices from trusted sources with complete extraction are automatically approved on creation.

### Auto-approval rules

| Source | Condition | Auto-approve? |
|--------|-----------|---------------|
| `:ksef` | Always | No |
| `:manual` | Complete extraction | Yes |
| `:pdf_upload` | Complete extraction | Yes |
| `:email` | Complete extraction AND sender is an active KSeF Hub member of the company | Yes |
| `:email` | Sender has no platform account or is not a member | No |
| Any | Extraction `:partial` or `:failed` | No |

### Email sender verification

For email-sourced invoices, "trusted sender" means:
1. The sender's email matches a registered KSeF Hub platform user (`Accounts.get_user_by_email/1`)
2. That user has an **active** membership in the specific company (`Companies.get_membership/2`)

Domain matching alone is NOT sufficient — sharing an `@company.com` domain does not grant trust.

### Implementation

A new pure module `KsefHub.Invoices.AutoApproval` encapsulates the decision logic. The `Invoices` context calls it after successful invoice creation and updates the status to `:approved` when appropriate. The setting is toggled via the existing company settings UI/API.

## Consequences

- Backwards compatible — default is `false`, no behavior change for existing companies
- Reduces manual work for companies that trust their own users' uploads and emails
- KSeF invoices always require verification, preserving the audit trail for external documents
- The auto-approval happens synchronously during creation, so the invoice is already `:approved` when the user sees it
- Auto-approved invoices can still be manually reset to `:pending` or `:rejected` if needed
