# KSeF Hub -- Design System

A branded design system for **KSeF Hub**, a financial operations portal for Polish companies. The product started as a KSeF (Krajowy System e-Faktur) integration -- certificate authentication, XAdES signing, FA(3) XML parsing, invoice sync, PDF generation -- and grew into a shared ledger: foreign expenses outside KSeF, ML-based categorization, duplicate detection, accountant access with permissions, and a REST API for downstream analytics. KSeF is now one of several inputs into the ledger, not the product itself.

> **Naming.** The service is called **KSeF Hub** (confirmed). Historical alternatives are kept in `brand/naming.md` as an artifact of the exploration; they are not in play. The logo is the **lattice mark** -- a 3x3 dot lattice with a teal center node and four teal spokes, signalling "graph of records / shared ledger with many connections."

## Sources

| Source | Where | Access notes |
|---|---|---|
| Phoenix/LiveView app code | Attached local folder `ksef_hub_web/` (controllers, live views, components) | Not bundled -- re-attach via the Import menu to iterate |
| Frontend assets | Attached local folder `assets/` (Tailwind v4 + DaisyUI + shadcn-style custom properties, Heroicons plugin, Cally calendar, Chart.js) | Not bundled |
| Existing token system | `assets/css/app.css` -- shadcn/ui-inspired tokens layered on top of DaisyUI themes (`light`, `dark`) | Ported to `colors_and_type.css` |
| Icon set | Heroicons (via the `hero-*` class plugin in `assets/vendor/heroicons.js`) | Linked from CDN as SVG sprite in kits |
| Core components | `lib/ksef_hub_web/components/core_components.ex` (badge, button, card, input, table, pagination, multi-select, date pickers) | Recreated as JSX in the UI kit |

## Index

```
.
+-- README.md                    <- you are here
+-- SKILL.md                     <- agent-skill manifest
+-- colors_and_type.css          <- all CSS vars (shadcn + DaisyUI), both themes
+-- brand/
|   +-- naming.md                <- naming rationale (KSeF Hub confirmed)
|   +-- logo.svg + logo-mark.svg <- lattice mark + wordmark lockup
+-- fonts/                       <- Geist + Geist Mono (via Google Fonts @import)
+-- assets/
|   +-- icons/                   <- Heroicons usage notes + CDN reference
|   +-- patterns/                <- subtle backgrounds (grid)
+-- preview/                     <- cards surfaced in the Design System tab
+-- ui_kits/
|   +-- admin/                   <- LiveView admin recreation (invoices, dashboard, cert, sync, settings)
|   +-- marketing/               <- public landing page
|   +-- docs/                    <- developer docs site
+-- slides/                      <- (none -- no deck template was provided)
```

## What this is for

Use this skill whenever you're designing **anything KSeF Hub-branded** -- admin screens, marketing pages, docs, throwaway prototypes, slide decks. The goals:

1. Stay faithful to the existing shadcn-on-DaisyUI token system already shipped in `assets/css/app.css` -- don't invent new color ramps.
2. Give the product a distinctive but restrained brand accent (teal `#0F766E` / oklch(52% 0.09 185)) that signals "compliant / synced" without fighting the neutral zinc base.
3. Keep copy dry, technical, infrastructure-grade -- Stripe/Linear voice, not SaaS-cheery.
4. Support EN primary + PL secondary in all UI.

---

## Content fundamentals

**Voice.** Dry, technical, precise. Operator-facing. The reader is a Polish accountant, a finance ops lead, or a developer integrating the REST API. They want confirmation that things are synced, signed, and stored -- not encouragement.

**Person.** Second person for imperatives ("Upload a new certificate"). Third person / product-voice for system messages ("Certificate expired", "Sync completed"). Never first-person ("we think..."). Never exclamation marks in admin UI.

**Casing.**
- **Sentence case** for button labels, section headers, table column headers shown as labels. Matches the existing code: `Sync Now`, `Invoices`, `Settings`.
- **UPPERCASE + wide tracking** only for table column headers (`text-xs uppercase tracking-wide`). See `core_components.ex` `table/1`.
- **lowercase** for badge text: `pending`, `approved`, `duplicate`, `needs review`, `incomplete`. This is load-bearing -- the badge component treats text as tokens.

**Tone examples -- pulled directly from the codebase.**

| Situation | Copy |
|---|---|
| Expired cert error | "Your KSeF certificate has expired. KSeF sync is no longer working. Please upload a new certificate to resume invoice synchronization." |
| Expiring soon | "Your KSeF certificate expires in 5 days." |
| Duplicate suspected | "This invoice may be a duplicate. View original." |
| Connection lost flash | "We can't find the internet" * "Attempting to reconnect" |
| Empty state (filter result, table has data elsewhere) | "No data for selected period" — *for zero-data states (`<EmptyState>`), see `DESIGN_SYSTEM.md` §7 at the repo root* |
| Pagination | "Showing 1-25 of 412 invoices" * "Page 3 of 17" |
| Manual action | "Sync Now" * "Not a duplicate" * "Confirm duplicate" |
| Prediction hint | "Predicted with 87.3% probability, feel free to adjust" * "Manually adjusted" |

**Polish/English.** UI is English-first. Polish appears in:
- Domain nouns that stay Polish: **Netto**, **Brutto**, **NIP**, **KSeF**, **FA(3)**, **XAdES**.
- Number formatting: `toLocaleString("pl-PL")` for amounts.
- Month labels use English short form (`Jan ... Dec`) in picker UI, but invoice dates render as `YYYY-MM-DD`.

**Emoji.** Used **only** as category labels (the `category_badge` component prepends `category.emoji` before the name). Never in UI chrome, buttons, banners, or marketing. No emoji-as-decoration.

**Iconography-as-text.** Never. Icons are always paired with labels in nav and buttons; icon-only buttons use `aria-label`. See `button/1` variant `"icon"`.

**Status vocabulary.** The app has a strict status lexicon -- use these exact words:
- Invoice status: `pending` * `approved` * `rejected` * `duplicate`
- Payment status: `pending` * `paid` * `voided`
- Extraction: `complete` * `partial` * `incomplete` * `failed`
- Prediction: `manual` * `needs_review`
- Sync job: `queued` * `running` * `completed` * `failed`
- Duplicate: `suspected` * `confirmed` * `dismissed`

---

## Visual foundations

### Color

**Base.** Zinc (OKLCH `oklch(21% 0.006 285.885)` for dark primary, `oklch(96.7% 0.001 286.375)` for light secondary). Neutral, flat, near-grayscale. Lifted directly from `app.css`.

**Semantic.**
- `--success` -- emerald/green, used for approved invoices, income badges, paid status.
- `--warning` -- amber, used for pending, expiring certs, "incomplete" extraction.
- `--error` / `--destructive` -- red, used for rejected, failed, expired, confirmed duplicates.
- `--info` -- blue, used for "needs review", `info` badges, tag lists.
- `--purple-500/*` -- used **only** for correction-type invoices (see `invoice_kind_badge`). Load-bearing.

**Brand accent.** Teal `oklch(52% 0.09 185)` (~`#0D7A76`). Applied to: logo mark, primary CTAs in marketing site, "synced" state indicator, the sync-status pill. NEVER use teal as `primary` in admin UI -- admin stays on zinc primary per the existing code.

**Usage rule.** Badges use the `{semantic}/10` background + `{semantic}/20` border + `{semantic}` text pattern -- already enforced by `badge/1`. Don't roll your own badge colors.

### Typography

- **Body / UI:** Geist, fallback to `ui-sans-serif, system-ui, -apple-system, sans-serif`. Loaded via Google Fonts.
- **Mono:** Geist Mono, used for: KSeF numbers, NIPs, invoice numbers (optionally), amounts in invoice detail tables, IBAN, PO numbers. Explicit rule from `invoice_details_table`.
- **Scale.** The codebase uses Tailwind default sizes. Display type in marketing uses `text-4xl` / `text-5xl`; admin headers are `text-lg font-semibold` (see `header/1`). Page titles in auth pages are `text-2xl font-semibold`.
- **Tracking.** `tracking-tight` on headings; `tracking-wide uppercase` on table column labels.
- **Font weight.** `400` body, `500` medium for labels and badges, `600` semibold for headers, `700` bold only for invoice Brutto totals.

### Spacing & radii

- **Base radius** `--radius: 0.5rem` (`rounded-md`). Cards use `rounded-xl`. Badges use `rounded-md`. Inputs use `rounded-md`. Buttons use `rounded-md`.
- **Spacing** uses Tailwind's default 4-px scale. Common rhythms seen in code: `p-4` (banners), `p-6` (cards), `gap-2 / gap-3 / gap-4`, `py-1.5 px-2` (table cells, nav items), `h-9` for input + default button height, `h-8` for small filter pills, `h-7` for sm buttons.
- **Borders** 1px. Color `var(--border)` = `oklch(92.2% 0.004 286.32)` light, `oklch(27.4% 0.006 286.033)` dark. Never thicker.

### Backgrounds & texture

- **Admin UI:** flat solid `bg-background`. No gradients, no patterns.
- **Marketing:** one subtle radial grid pattern on hero (see `assets/patterns/grid.svg`). No illustrations, no 3D, no mesh gradients.
- **Docs:** same flat neutral as admin.

### Animation

- **Only** what LiveView already does: `topbar` loading indicator (`#29d` blue, 300ms show delay), `motion-safe:animate-spin` on loading icons, CSS transitions on hover/focus (`transition-colors`, ~150ms default).
- Flash toasts: `transition-all ease-out 300ms` on show, `ease-in 200ms` on hide, combined translate-y + scale + opacity. See `show/hide` helpers.
- No bounces, no entrance choreography, no scroll-jacking in marketing.

### Hover & press

- **Hover:** `hover:bg-shad-accent hover:text-shad-accent-foreground` for ghost/outline buttons and nav items. For primary buttons: `hover:bg-shad-primary/90`. Links: `underline-offset-4 hover:underline`.
- **Press / active:** no custom active state; rely on browser focus + `focus-visible:ring-1 focus-visible:ring-ring`.
- **Disabled:** `disabled:pointer-events-none disabled:opacity-50`.
- **Cursor:** `cursor-pointer` is explicitly applied to interactive elements -- it is not the browser default here because Tailwind resets it.

### Shadows & elevation

- **Flat by default.** `--depth: 0` in DaisyUI theme config. Most UI has zero shadow.
- Dropdown popovers (`dropdown-content`, date picker popovers) use `shadow-md` (light) or `shadow-lg` (calendar).
- Flash toast uses no shadow -- relies on border + background.
- No inset shadows. No colored glows.

### Transparency & blur

- Top navbar: `bg-background/95 backdrop-blur supports-backdrop-filter:bg-background/60`. This is the **only** place `backdrop-blur` is used.
- Background tints on banners/cards use `/5` or `/10` opacity on semantic colors (`bg-warning/5`, `bg-error/10`). Borders use `/20` or `/50`.

### Cards

- Border: `border border-border`.
- Radius: `rounded-xl` for content cards, `rounded-lg` for table containers, `rounded-md` for everything else.
- Shadow: none.
- Padding default: `p-6`.
- Background: `bg-card` (= `--background` in both themes).

### Layout rules

- Sticky top navbar, 56px tall (`h-14`), full-width, backdrop-blurred.
- Main content: `max-w-7xl mx-auto p-4 sm:p-6 lg:p-8`.
- Tables wrap in `rounded-lg border overflow-hidden` containers with `overflow-x-auto`.
- Mobile: nav collapses into a `hero-bars-3` dropdown. Company selector label hides below `sm`.

### Imagery vibe

The product has no hero imagery in-app. For marketing, imagery should be: **warm-neutral, document-forward, slightly grainy, high-contrast b&w or desaturated**. Think tax-office paperwork close-ups, monitor macros. No stock photos of smiling teams.

---

## Iconography

**Primary icon library: Heroicons.** The app uses Heroicons via a Tailwind plugin (`assets/vendor/heroicons.js`) that generates `hero-<name>` classes. Components reference icons as `<.icon name="hero-document-text" />` etc. Outline is default; `-solid` and `-mini` suffixes switch weight.

**Icon set size.** ~24px outline on desktop, 16px (`size-4`) inline with text. `size-3.5` for compact pills, `size-5` for banner icons.

**Icons observed in the codebase** (keep to this vocabulary unless absolutely necessary):

| Purpose | Icon |
|---|---|
| Invoices | `hero-document-text` |
| Payments | `hero-banknotes` |
| Dashboard | `hero-home` |
| Companies | `hero-building-office-2` |
| Settings | `hero-cog-6-tooth` |
| Sync / reload | `hero-arrow-path` |
| Search | `hero-magnifying-glass` |
| Calendar | `hero-calendar-days` |
| Chevrons | `hero-chevron-down`, `hero-chevron-left`, `hero-chevron-right` |
| Close | `hero-x-mark` |
| Info | `hero-information-circle` |
| Warning | `hero-exclamation-triangle` |
| Error | `hero-exclamation-circle` / `hero-x-circle` |
| Correction | `hero-arrow-uturn-left` |
| Duplicate | `hero-document-duplicate` |
| Log out | `hero-arrow-right-on-rectangle` |
| Theme | `hero-sun-micro` / `hero-moon-micro` / `hero-computer-desktop-micro` |
| Mobile menu | `hero-bars-3` |

**Substitution flag.** Heroicons are linked from the jsDelivr CDN in the UI kits (they're standard/public; no substitution). No custom SVG icons in the codebase to copy out.

**Emoji as icons.** Used **only** on category badges (`category.emoji`). Not elsewhere.

**Unicode as icons.** Never.

**Logo.** The current code renders a text logo: `hero-document-text` + "Invoi" + "by Appunite". This is a placeholder. See `brand/logo.svg` for the working replacement.

---

## Font substitution

**Geist / Geist Mono** -- loaded via Google Fonts `@import` in `colors_and_type.css`. No local .ttf/.otf files are bundled (none were in the repo either; the codebase just declares `font-family: Geist` expecting the end user to self-host or proxy).

> **If you need offline TTFs**, please attach them -- I used the Google Fonts CDN version, which is visually identical but adds a network dependency.

---

## UI kits

- `ui_kits/admin/` -- LiveView admin recreation (the primary surface). Fully interactive: login, invoices list + detail, dashboard, settings.
- `ui_kits/marketing/` and `ui_kits/docs/` -- **not built yet**; scoped but deferred. Ask when you want them.

## SKILL.md

See `SKILL.md` for the agent-skill manifest. This design system is intended to be usable as a Claude Code skill.

---

## Caveats

1. **Name confirmed: KSeF Hub.** Logo finalized as the lattice mark.
2. **Brand teal is additive.** The existing admin is zinc-on-zinc shadcn neutral; teal appears on the logo mark and a few marketing-leaning accents, not as `--primary`.
3. **Marketing + docs kits** are not yet built. Request them when ready.
4. **No deck template was provided** -- `slides/` is empty.
5. **Geist fonts** come via Google Fonts CDN. Attach local TTFs if you need offline.
