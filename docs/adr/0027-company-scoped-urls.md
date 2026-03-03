# 0027. Company-Scoped URLs

Date: 2026-03-03

## Status

Accepted

## Context

When a user pasted a URL like `/invoices/:id` that belonged to a different company than the one in their session, they would see "Invoice not found" and get redirected. This happened because the company context was stored only in the server-side session, making URLs non-shareable and context-dependent.

Additionally, when sharing links between team members who might belong to multiple companies, the recipient's session company might not match the sender's intent.

## Decision

Embed the company context directly in the URL by moving all company-scoped routes under `/c/:company_id/...`.

**New URL structure:**
- `/c/:company_id/invoices` — invoice list
- `/c/:company_id/invoices/:id` — invoice detail
- `/c/:company_id/invoices/:id/pdf` — PDF download
- `/c/:company_id/dashboard` — dashboard
- `/c/:company_id/certificates` — certificates
- `/c/:company_id/tokens` — API tokens
- `/c/:company_id/team` — team management
- `/c/:company_id/categories` — categories
- `/c/:company_id/tags` — tags
- `/c/:company_id/syncs` — sync jobs
- `/c/:company_id/exports` — exports

**Routes that remain at the top level (not company-scoped):**
- `/companies`, `/companies/new`, `/companies/:id/edit` — company management
- `/switch-company/:id` — company switching
- Auth routes (`/users/*`, `/auth/*`)
- `/` — home page
- API routes (`/api/*`) — already scoped via bearer token

**Company resolution priority in LiveAuth:**
1. URL `company_id` param (highest priority)
2. Session `current_company_id`
3. User's first company (fallback)

**Company switching:** When a user switches companies via the dropdown, the `CompanySwitchController` rewrites the `/c/:old_id/...` segment in the `return_to` path to `/c/:new_id/...`.

**No legacy redirect support:** Old flat URLs (`/invoices`, `/dashboard`, etc.) simply return errors. This avoids complexity and encourages immediate adoption of the new URL structure.

## Consequences

**Benefits:**
- URLs are self-contained and shareable — pasting a link always shows the correct company context
- Browser history and bookmarks work correctly across companies
- Multiple browser tabs can show different companies simultaneously
- Deep-linking into specific invoices works across company boundaries (for users with access)

**Trade-offs:**
- URLs are longer (`/c/:uuid/invoices` vs `/invoices`)
- All `~p` sigils in LiveViews and templates need `@current_company.id`
- Old bookmarks and shared links break immediately (no legacy redirects)
- The company switcher must rewrite URLs when changing companies
