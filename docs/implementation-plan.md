# Implementation Plan: Multi-Tenant SaaS Migration

## Context

KSeF Hub is transitioning from an internal tool (Google Sign-In + email allowlist, flat access) to a self-service multi-tenant SaaS. The architectural decisions are documented in ADRs 0011-0014. The codebase already has company-scoped data (credentials, invoices, checkpoints) but lacks access control, user-scoped certificates, email/password auth, and invitations.

This plan breaks the migration into 5 PRs, each on its own feature branch, each independently reviewable and deployable.

**References:**
- ADR 0011: Per-Company RBAC (`docs/adr/0011-per-company-rbac.md`)
- ADR 0012: User-Scoped Certificates (`docs/adr/0012-user-scoped-certificates.md`)
- ADR 0013: Email/Password Auth (`docs/adr/0013-email-password-auth.md`)
- ADR 0014: Company Invitation System (`docs/adr/0014-company-invitation-system.md`)
- PRD: `docs/prd.md` (Implementation Phases section)
- Certificate docs: `docs/ksef-certificates.md`

**Existing patterns to follow:**
- Schemas: `@type t`, `@primary_key {:id, :binary_id}`, `belongs_to :company`, `timestamps()` — see `lib/ksef_hub/credentials/credential.ex`
- Contexts: company_id as first param, `where([t], t.company_id == ^company_id)` scoping — see `lib/ksef_hub/credentials.ex`
- Factories: ExMachina with `build(:association)` — see `test/support/factory.ex`
- Tests: `use KsefHub.DataCase, async: true`, setup with factories, Mox for externals — see `test/ksef_hub/invoices_test.exs`
- Migrations: `binary_id` PKs, `on_delete: :restrict`, compound unique indexes — see `priv/repo/migrations/20260208000002_add_company_id_to_credentials.exs`
- LiveAuth: `on_mount` loads user + companies into socket — see `lib/ksef_hub_web/live/live_auth.ex`

---

## PR 1: Per-Company Memberships (RBAC Foundation)

**Branch:** `feat/memberships-rbac`
**ADR:** `docs/adr/0011-per-company-rbac.md` — memberships table, 3 roles, enforcement at context + LiveView + API layers
**PRD:** F1c (Company Management), F6.1 (Company selector), Users/Roles table
**Depends on:** nothing (first PR)

### What changes

Introduce `memberships` table joining users to companies with a role. Update `LiveAuth` to load only the user's companies. Update `CompanySwitchController` to verify membership. Add role-based visibility to LiveView pages.

### Checklist

#### 1.1 Membership schema + migration
- [x] Write test: `test/ksef_hub/companies/membership_test.exs` — changeset validations (required fields, role enum, unique user+company)
- [x] Create migration: `create_memberships` table (id, user_id, company_id, role, timestamps). Unique index on `[:user_id, :company_id]`. FK to users (cascade) and companies (restrict). Index on company_id.
- [x] Create schema: `lib/ksef_hub/companies/membership.ex` — fields, `@type t`, changeset with `validate_inclusion(:role, ~w(owner accountant invoice_reviewer))`
- [x] Add factory: `:membership` in `test/support/factory.ex` — builds user + company, default role `"owner"`
- [x] Run tests green

#### 1.2 Companies context — membership functions
- [x] Write tests in `test/ksef_hub/companies_test.exs`:
  - `list_companies_for_user/1` returns only companies where user has membership
  - `get_membership/2` returns membership for user+company pair
  - `get_membership!/2` raises on missing
  - `create_membership/1` creates with valid attrs, rejects duplicate
  - `create_company_with_owner/2` atomically creates company + owner membership (Ecto.Multi)
  - `has_role?/3` checks if user has specific role for company
  - `authorize/3` returns `{:ok, membership}` or `{:error, :unauthorized}`
- [x] Implement in `lib/ksef_hub/companies.ex`:
  - `list_companies_for_user(user_id)` — join through memberships
  - `list_companies_for_user_with_credential_status(user_id)` — replaces current `list_companies_with_credential_status/0`
  - `get_membership(user_id, company_id)` / `get_membership!(user_id, company_id)`
  - `create_membership(attrs)`
  - `create_company_with_owner(user, company_attrs)` — Multi: insert company + insert membership(role: owner)
  - `has_role?(user_id, company_id, role_or_roles)`
  - `authorize(user_id, company_id, required_roles)`
- [x] Run tests green

#### 1.3 Data migration — existing users become owners
- [x] Create migration: for each company, find or create owner membership for the first user (or all users if that matches current behavior)
- [x] Run tests green

#### 1.4 LiveAuth — load only user's companies
- [x] Write/update test: `test/ksef_hub_web/live/live_auth_test.exs`
  - User with memberships sees only their companies
  - User with no memberships gets empty companies list
  - `current_company` is from user's companies only
  - Role is assigned to socket (`socket.assigns.current_role`)
- [x] Update `lib/ksef_hub_web/live/live_auth.ex`:
  - Replace `Companies.list_companies()` with `Companies.list_companies_for_user(user.id)`
  - Load membership for current company, assign `:current_role` to socket
  - If user has no companies → redirect to company creation page
- [x] Run tests green

#### 1.5 CompanySwitchController — verify membership
- [x] Write/update test: `test/ksef_hub_web/controllers/company_switch_controller_test.exs`
  - User WITH membership can switch → 302 redirect
  - User WITHOUT membership gets 403/redirect with flash
- [x] Update `lib/ksef_hub_web/controllers/company_switch_controller.ex` — check membership before setting session
- [x] Run tests green

#### 1.6 Role-based UI visibility
- [x] Write tests: LiveView tests verifying owner sees Certificates/Tokens tabs, non-owner does not
  - Test `DashboardLive` or layout component renders tabs conditionally
- [x] Add `current_role` checks in LiveView templates — owner-only tabs: Certificates, API Tokens, (future) Team
- [x] Run tests green

#### 1.7 Company creation page
- [x] Write test: `test/ksef_hub_web/live/company_live_test.exs` — creating company auto-creates owner membership
- [x] Update `CompanyLive.Index` or create `CompanyLive.New` — form calls `Companies.create_company_with_owner/2`
- [x] Run tests green

#### 1.8 Final verification
- [x] `mix test` — all green
- [x] `mix format --check-formatted`
- [x] `mix credo --strict`
- [ ] Manual smoke test: existing user sees their companies, can switch, role-based tabs work

---

## PR 2: User-Scoped KSeF Certificates

**Branch:** `feat/user-scoped-certificates`
**ADR:** `docs/adr/0012-user-scoped-certificates.md` — cert belongs to person (PESEL), not company; `user_certificates` table
**PRD:** F2 (KSeF Certificate), also see `docs/ksef-certificates.md` for domain context
**Depends on:** PR 1 (memberships, for owner lookup in sync worker)

### What changes

Create `user_certificates` table at user level. Strip cert data from `ksef_credentials` (becomes sync config only). Update sync worker to find owner's cert via membership. Update CertificateLive to be user-level.

### Checklist

#### 2.1 UserCertificate schema + migration
- [x] Write test: `test/ksef_hub/credentials/user_certificate_test.exs` — changeset validations
- [x] Create migration: `create_user_certificates` table (id, user_id FK cascade, certificate_data_encrypted, certificate_password_encrypted, certificate_subject, not_before, not_after, fingerprint, is_active, timestamps). Index on user_id. Unique index on `[:user_id]` where `is_active = true` (one active cert per user).
- [x] Create schema: `lib/ksef_hub/credentials/user_certificate.ex`
- [x] Add factory: `:user_certificate` in factory.ex
- [x] Run tests green

#### 2.2 Credentials context — user certificate functions
- [x] Write tests in `test/ksef_hub/credentials_test.exs`:
  - `get_active_user_certificate(user_id)` — returns active cert or nil
  - `create_user_certificate(user, attrs)` — encrypts and stores
  - `replace_active_user_certificate(user_id, attrs)` — deactivate old, create new (Multi)
  - `get_certificate_for_company(company_id)` — finds owner via membership, returns their cert
- [x] Implement in `lib/ksef_hub/credentials.ex`:
  - User certificate CRUD functions
  - `get_certificate_for_company(company_id)` — join: company → membership(owner) → user → user_certificate(active)
- [x] Run tests green

#### 2.3 Migration — move cert data from ksef_credentials to user_certificates
- [x] Create data migration: for each credential with cert data, create user_certificate for the company's owner
- [x] Create migration: remove `certificate_data_encrypted`, `certificate_password_encrypted`, `certificate_subject`, `certificate_expires_at` columns from `ksef_credentials`
- [x] Run tests green

#### 2.4 Sync worker — load cert via membership
- [x] Write/update test: `test/ksef_hub/sync/sync_worker_test.exs`
  - Worker loads owner's cert for the company
  - Worker fails gracefully if no owner cert exists
- [x] Update `lib/ksef_hub/sync/sync_worker.ex` — replace `load_active_credential` to use `Credentials.get_certificate_for_company(company_id)` for cert data, keep credential for NIP/sync state
- [x] Run tests green

#### 2.5 CertificateLive — user-level upload
- [x] Write/update test: `test/ksef_hub_web/live/certificate_live_test.exs`
  - Owner can upload cert (stored at user level)
  - Non-owner cannot access page
  - Cert info displayed from user_certificate
- [x] Update `lib/ksef_hub_web/live/certificate_live.ex` — upload writes to `user_certificates`, display reads from `user_certificates`, owner-only access check on mount
- [x] Run tests green

#### 2.6 Credential schema cleanup
- [x] Update `lib/ksef_hub/credentials/credential.ex` — remove cert fields from schema
- [x] Update any remaining references to cert fields on credentials
- [x] Run tests green

#### 2.7 Final verification
- [x] `mix test` — all green
- [x] `mix format --check-formatted`
- [x] `mix credo --strict`

---

## PR 3: Email/Password Authentication

**Branch:** `feat/email-password-auth`
**ADR:** `docs/adr/0013-email-password-auth.md` — replaces Google Sign-In + ALLOWED_EMAILS with open sign-up
**PRD:** F1 (Authentication: F1.1-F1.5)
**Depends on:** PR 1 (memberships, for post-login company redirect)

### What changes

Add email/password auth (phx.gen.auth pattern). Keep Google Sign-In as alternate path. Remove ALLOWED_EMAILS gate. Add registration, login, confirmation, password reset.

### Checklist

#### 3.1 User schema updates + auth tokens table
- [ ] Create migration: add `hashed_password` (nullable initially, for Google-only users), `confirmed_at` to `users` table. Create `users_tokens` table (id, user_id, token binary, context string, sent_to, timestamps).
- [ ] Update `lib/ksef_hub/accounts/user.ex` — add `hashed_password`, `confirmed_at` fields. Add `registration_changeset/2`, `password_changeset/2`, `confirm_changeset/1`, `email_changeset/2`. Add password hashing (Bcrypt/Argon2).
- [ ] Create `lib/ksef_hub/accounts/user_token.ex` — schema for session/confirmation/reset tokens
- [ ] Run tests green

#### 3.2 Accounts context — auth functions
- [ ] Write tests in `test/ksef_hub/accounts_test.exs`:
  - `register_user/1` — creates user with hashed password
  - `get_user_by_email_and_password/2` — validates credentials
  - `generate_user_session_token/1` / `get_user_by_session_token/1`
  - `deliver_user_confirmation_instructions/2`
  - `confirm_user/1`
  - `deliver_user_reset_password_instructions/2`
  - `reset_user_password/2`
  - `get_or_create_google_user/1` — finds by email or creates with confirmed_at set
- [ ] Implement in `lib/ksef_hub/accounts.ex` — follow phx.gen.auth patterns
- [ ] Run tests green

#### 3.3 Auth controllers + LiveViews
- [ ] Create registration page: `lib/ksef_hub_web/live/user_registration_live.ex`
- [ ] Create login page: `lib/ksef_hub_web/live/user_login_live.ex`
- [ ] Create session controller: `lib/ksef_hub_web/controllers/user_session_controller.ex`
- [ ] Create confirmation flow: `lib/ksef_hub_web/live/user_confirmation_live.ex`
- [ ] Create password reset: `lib/ksef_hub_web/live/user_forgot_password_live.ex`, `user_reset_password_live.ex`
- [ ] Write tests for each (registration, login, logout, confirmation, reset)
- [ ] Run tests green

#### 3.4 Update router + auth plugs
- [ ] Update `lib/ksef_hub_web/router.ex` — add auth routes (register, login, logout, confirm, reset)
- [ ] Update `lib/ksef_hub_web/plugs/require_auth.ex` — use session token instead of raw user_id
- [ ] Update `LiveAuth` — use new session token approach
- [ ] Run tests green

#### 3.5 Google Sign-In integration
- [ ] Update `lib/ksef_hub_web/controllers/auth_controller.ex`:
  - Remove `ALLOWED_EMAILS` check
  - On callback: `Accounts.get_or_create_google_user/1` → create session token → redirect
- [ ] Write tests: Google login for new user, Google login for existing user
- [ ] Run tests green

#### 3.6 Post-login flow
- [ ] User with no companies → redirect to company creation
- [ ] User with companies → redirect to dashboard (first company or last-used)
- [ ] Write tests for redirect logic
- [ ] Run tests green

#### 3.7 Email delivery setup
- [ ] Add Swoosh dependency (if not already present)
- [ ] Create `lib/ksef_hub/accounts/user_notifier.ex` — confirmation/reset email templates
- [ ] Configure Swoosh adapter (Mailgun/SMTP for prod, local for dev/test)
- [ ] Run tests green

#### 3.8 Final verification
- [ ] `mix test` — all green
- [ ] `mix format --check-formatted`
- [ ] `mix credo --strict`
- [ ] Remove `ALLOWED_EMAILS` from config/runtime.exs, docs, CLAUDE.md references

---

## PR 4: Company Invitation System

**Branch:** `feat/company-invitations`
**ADR:** `docs/adr/0014-company-invitation-system.md` — hashed token, 7-day expiry, auto-accept on sign-up
**PRD:** F1d (Team & Invitations: F1d.1-F1d.7), F6.7 (Team management page)
**Depends on:** PR 1 (memberships), PR 3 (email/password auth, email delivery)

### What changes

Add invitations table. Owner invites by email + role. Tokenized accept link via email. Auto-accept on sign-up if pending invitation exists. Team management LiveView.

### Checklist

#### 4.1 Invitation schema + migration
- [x] Write test: `test/ksef_hub/invitations/invitation_test.exs` — changeset validations
- [x] Create migration: `create_invitations` table (id, company_id FK restrict, email, role, invited_by_id FK, token_hash, status enum, expires_at, timestamps). Unique partial index on `[:company_id, :email]` where `status = 'pending'`.
- [x] Create schema: `lib/ksef_hub/invitations/invitation.ex`
- [x] Add factory: `:invitation` in factory.ex
- [x] Run tests green

#### 4.2 Invitations context
- [x] Write tests in `test/ksef_hub/invitations_test.exs`:
  - `create_invitation/2` — owner creates, token generated, hashed in DB
  - `create_invitation/2` — rejects if email already has membership
  - `create_invitation/2` — rejects if pending invitation already exists
  - `create_invitation/2` — rejects non-owner caller
  - `accept_invitation/1` — token valid, creates membership, marks accepted
  - `accept_invitation/1` — rejects expired token
  - `cancel_invitation/2` — owner cancels pending invitation
  - `list_pending_invitations/1` — for a company
  - `accept_pending_invitations_for_email/1` — auto-accept on sign-up
- [x] Create `lib/ksef_hub/invitations.ex` context module
- [x] Run tests green

#### 4.3 Invitation email
- [x] Create `lib/ksef_hub/invitations/invitation_notifier.ex` — email with accept link
- [x] Write test: email contains correct token URL, company name, role
- [x] Run tests green

#### 4.4 Accept flow (controller/LiveView)
- [x] Create accept page: `lib/ksef_hub_web/live/invitation_accept_live.ex`
  - Validates token
  - If logged in → accept, redirect to company dashboard
  - If not logged in → redirect to sign-up/login with return URL
- [x] Write tests for accept flow (valid token, expired, already member)
- [x] Run tests green

#### 4.5 Auto-accept on sign-up
- [x] Update registration/Google sign-in flow: after creating user, call `Invitations.accept_pending_invitations_for_email(email)`
- [x] Write test: sign up with pending invitation → membership auto-created
- [x] Run tests green

#### 4.6 Team management LiveView
- [x] Write test: `test/ksef_hub_web/live/team_live_test.exs`
  - Owner sees member list, invite form, pending invitations
  - Non-owner cannot access
  - Owner can invite, cancel, remove member
- [x] Create `lib/ksef_hub_web/live/team_live.ex` — owner-only page
- [x] Add route: `live "/team", TeamLive`
- [x] Run tests green

#### 4.7 Final verification
- [x] `mix test` — all green
- [x] `mix format --check-formatted`
- [x] `mix credo --strict`

---

## PR 5: API Token Company Scoping

**Branch:** `feat/api-token-scoping`
**ADR:** `docs/adr/0006-api-token-hashed-bearer.md` (updated status), `docs/adr/0011-per-company-rbac.md` (owner-only token mgmt)
**PRD:** F1b (API Token Management: F1b.1-F1b.6)
**Depends on:** PR 1 (memberships)

### What changes

Add `company_id` to API tokens. API auth derives company from token (no more query param). Only owners create/revoke tokens. Update OpenAPI specs.

### Checklist

#### 5.1 API token schema + migration
- [x] Create migration: add `company_id` (FK restrict) to `api_tokens`. Data migration: associate existing tokens with a company (or mark inactive).
- [x] Update `lib/ksef_hub/accounts/api_token.ex` — add `belongs_to :company`, update changeset
- [x] Write tests for updated changeset
- [x] Run tests green

#### 5.2 Accounts context updates
- [x] Write tests:
  - `create_api_token/3` — requires user_id, company_id, attrs; verifies user is owner
  - `validate_api_token/1` — returns token with company preloaded
  - `list_api_tokens/2` — scoped to user + company
  - `revoke_api_token/3` — user_id + company_id + token_id; owner only
- [x] Update `lib/ksef_hub/accounts.ex`
- [x] Run tests green

#### 5.3 ApiAuth plug — derive company from token
- [x] Write/update test: `test/ksef_hub_web/plugs/api_auth_test.exs`
  - Valid token assigns `api_token` AND `current_company` to conn
- [x] Update `lib/ksef_hub_web/plugs/api_auth.ex` — preload company on token, assign to conn
- [x] Run tests green

#### 5.4 API controllers — remove company_id param
- [x] Update `lib/ksef_hub_web/controllers/api/invoice_controller.ex` — get company from `conn.assigns.current_company` instead of query param
- [x] Update OpenAPI specs — remove `company_id` from query parameters
- [x] Write tests: API calls use token's company, not a param
- [x] Run tests green

#### 5.5 Token management UI — owner only, company scoped
- [x] Update `TokenLive` — show only tokens for current company, owner-only access
- [x] Write tests
- [x] Run tests green

#### 5.6 Final verification
- [x] `mix test` — all green
- [x] `mix format --check-formatted`
- [x] `mix credo --strict`

---

## Dependency Graph

```
PR 1 (Memberships) ──→ PR 2 (User Certificates)
         │
         ├──────────→ PR 3 (Email/Password Auth) ──→ PR 4 (Invitations)
         │
         └──────────→ PR 5 (API Token Scoping)
```

PR 1 must merge first. After that, PRs 2, 3, and 5 can proceed in parallel. PR 4 requires PR 3.

## Progress Tracking

When starting work on a PR, update the status below. This lets a new LLM context pick up where the previous left off.

| PR | Branch | Status | Notes |
|----|--------|--------|-------|
| 1 | `feat/memberships-rbac` | DONE | |
| 2 | `feat/user-scoped-certificates` | DONE | |
| 3 | `feat/email-password-auth` | DONE | |
| 4 | `feat/company-invitations` | DONE | |
| 5 | `feat/api-token-scoping` | DONE | |

## Code Quality Standards

**Every module must have:**
- `@moduledoc` describing purpose
- `@type t :: %__MODULE__{}` on all Ecto schemas
- `@doc` on every public function
- `@spec` on every function (public and private)

**Code style:**
- No dead code, no commented-out code, no TODOs left behind
- No debug statements (`IO.inspect`, `Logger.debug` for temp debugging)
- Pattern matching in function heads over conditionals
- `with` for multi-step fallible operations
- `|>` pipelines for data transformation
- Small, focused functions (< 15 lines)
- Extract shared logic into dedicated modules — never copy-paste
- Depend on behaviours, not concrete implementations
- Guard clauses where appropriate
- Clean, descriptive names — code is read many more times than written

**Tests must be:**
- Thorough — cover happy path, error cases, edge cases, and data isolation
- Well-named — `describe` blocks mirror function names, `test` blocks describe behavior
- Isolated — `async: true` where possible, factory-built data, Mox for externals
- Readable — a test is documentation; another developer should understand the expected behavior by reading the test alone

## TDD Workflow Reminder

For every checklist item:
1. **Red** — write the failing test first
2. **Green** — write minimum code to pass
3. **Refactor** — clean up, extract shared logic, ensure DRY/SOLID, verify all docs/specs present

## ADR ↔ PR ↔ PRD Cross-Reference

| PR | ADR | PRD Sections | Key Decision |
|----|-----|-------------|--------------|
| 1 | `docs/adr/0011-per-company-rbac.md` | F1c (Company Mgmt), F6.1 (Company selector), Users/Roles table | `memberships` table with owner/accountant/invoice_reviewer roles |
| 2 | `docs/adr/0012-user-scoped-certificates.md` | F2 (Certificate), `docs/ksef-certificates.md` | `user_certificates` table; cert belongs to person, not company |
| 3 | `docs/adr/0013-email-password-auth.md` | F1 (Auth), supersedes ADRs 0006+0008 auth model | `phx.gen.auth` email/password; Google Sign-In optional; remove ALLOWED_EMAILS |
| 4 | `docs/adr/0014-company-invitation-system.md` | F1d (Team & Invitations), F6.7 (Team page) | `invitations` table; hashed token; 7-day expiry; auto-accept on sign-up |
| 5 | `docs/adr/0006-api-token-hashed-bearer.md` (updated) | F1b (API Token Mgmt) | Add company_id to api_tokens; derive company from token |

## Common Mistakes

Lessons learned from PR review rounds. Apply these proactively when implementing new features.

> **Living document:** After each PR review cycle, add new lessons here. This compounds over time — later PRs benefit from all prior review feedback, reducing review rounds and improving first-pass quality.

### Changesets & Security

- **Never cast foreign key IDs in changesets.** Set `user_id`, `company_id`, etc. on the struct before calling `changeset/2`. Only cast fields the user should control (e.g., `:role`). This prevents mass-assignment attacks.
- **Test security boundaries explicitly.** Add tests for mass-assignment, open-redirect (`https://evil.com`, `//evil.com`), unauthorized access, and cross-tenant data leakage — not just happy paths.
- **Guard against nil session values in controllers.** Use `user_id when is_binary(user_id)` pattern matching in `with` chains to catch missing session data early.

### LiveView Tests

- **Use `has_element?/2,3` with stable CSS selectors** instead of `html =~ "string"`. Prefer `has_element?(view, "a[href='/dashboard']")` over checking raw HTML strings. String matching is brittle and breaks on markup changes.
- **Add `data-testid` attributes to UI elements** that tests need to target. This decouples tests from styling and text content: `has_element?(view, "[data-testid='current-company-name']", "My Company")`.
- **Use precise form selectors** when pages have multiple forms. Use `form("form[phx-submit=save]", ...)` instead of bare `form("form", ...)`.

### Type Specs & Code Quality

- **Use specific types in `@spec`** — prefer `Company.t()` over `map()`, `Membership.t()` over `map()`. Generic types hide bugs and weaken Dialyzer.
- **Avoid redundant DB lookups.** When resolving fallbacks (e.g., current company), compute derived values from already-loaded data. Don't call the DB twice when one pass suffices.
- **Use `assert is_nil(value)`** over `refute value == something` — the former is a stronger, more precise assertion.

### Documentation & Markdown

- **Always add language identifiers to fenced code blocks** in markdown files. Use ` ```text `, ` ```elixir `, ` ```sql `, etc. — never bare ` ``` `.
- **Differentiate role descriptions** in schema moduledocs. Don't just list role names — explain what each role can do.

### Database & Queries

- **Add explicit indexes for query patterns** even when a composite index exists with the right leading column. A dedicated single-column index on `user_id` is still valuable for queries that only filter by user.
- **Test data isolation.** When updating `on_mount` hooks or context functions to scope by user/company, ensure all existing tests create the necessary association records (e.g., memberships). A single missing `insert(:membership)` in setup will cascade into redirect-based test failures.
- **Always add `order_by` + `limit(1)` to `Repo.one()` queries that join through associations.** Joins can produce multiple rows (e.g., multiple owner memberships). Without `limit(1)`, `Repo.one()` raises `Ecto.MultipleResultsError`. Pick a deterministic order (e.g., `desc: inserted_at`).
- **Guard nullable columns in data migration SQL.** When `INSERT INTO ... SELECT` copies data between tables, add `IS NOT NULL` checks for every non-nullable target column — even if the source "should" always have data. Prevents migration failures on dirty data.
- **Make data migrations irreversible.** A `down/0` that does `DELETE FROM table` will destroy post-migration user data. Either `raise Ecto.MigrationError` in `down/0` or track migrated rows with a source column so rollback only removes originally migrated records.
- **Use 3-arity `remove/3` in column-removal migrations.** `remove :col, :type` is irreversible. `remove(:col, :type, null: true)` gives Ecto enough info to recreate the column on rollback.

### Factories & Test Data

- **Use `params_for/2` from ExMachina instead of inline attribute maps.** Inline maps drift from factory defaults over time. Use `params_for(:factory) |> Map.merge(%{override: value})` to keep test data consistent and centralized.
- **Keep `@spec` and `@doc` return types in sync with implementation.** When a function starts returning a new field (e.g., adding `not_before` to a certificate info map), update the `@spec` and `@doc` immediately — stale specs mislead callers.

### LiveView & UI

- **Don't silently discard errors in helper functions.** If a side-effect like credential creation can fail, at minimum `Logger.warning` the error. Silent `:ok` returns hide broken state.
- **Handle nil metadata gracefully in templates.** When displaying records that may have been created before new fields were added, always show the field labels with fallback text (e.g., "—") rather than hiding them with `:if` guards. An empty card with just "Uploaded" is confusing.
- **Keep dashboard status indicators consistent with the data model.** When the data model changes (e.g., certificates move from company-level to user-level), update all status indicators. A `cert_active` flag that only checks credential existence but ignores the actual certificate misleads users.

---

## Context Recovery Instructions

If starting a new LLM context mid-implementation:
1. Read this file for overall plan and progress
2. Read the relevant ADR for the current PR (see table above)
3. Read `CLAUDE.md` for project conventions (TDD, code style, architecture)
4. Check `git branch` and `git log --oneline -10` to see current state
5. Check the checklist above — items marked `[x]` are done
6. Run `mix test` to verify current state
7. Continue from the first unchecked item in the current PR
