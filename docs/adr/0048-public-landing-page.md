---
name: Public landing page as standalone Astro project
description: Ship the KSeF Hub public marketing site as a separate Astro 5 + Tailwind v4 project in the same monorepo, deployed to GitHub Pages. Zero runtime coupling with the Phoenix app.
tags: [landing, marketing, astro, seo, i18n, deployment]
author: emil
date: 2026-04-20
status: Accepted
---

# 0048. Public Landing Page as Standalone Astro Project

Date: 2026-04-20

## Status

Accepted

## Context

KSeF Hub needs a public marketing surface — a place for prospects, OSS contributors, and search engines to find the product. Constraints that shaped the approach:

- **Cost-optimized.** KSeF Hub is open-source and will have many self-hosted instances. The landing represents the project itself (centrally hosted by us), not something that ships with the product. Target cost: free.
- **CDN-cacheable.** Landing traffic must not hit the Phoenix app; marketing spikes cannot pressure the product runtime.
- **Different deployment from the admin app.** No shared container, no shared build, no shared runtime. OSS operators run Phoenix; only we run the landing.
- **Part of the dev pipeline.** Same repo, same PR flow — not a separate project to clone.
- **Shared brand foundation, divergent visual language.** Marketing is airier; admin is denser. They agree on colors/type tokens, not layout.
- **Iterable for SEO.** Polish is the primary audience (KSeF is a Polish mandate). Long-form content (blog, docs, changelog) is expected to follow.

Alternatives considered and rejected:

| Option | Why rejected |
|--------|--------------|
| Phoenix controller + HEEx | Couples landing uptime and scale to the product. Every visitor touches the BEAM. Wrong scaling story. |
| Tableau / NimblePublisher (Elixir SSG) | Same stack, but the Elixir SSG ecosystem meaningfully lags Astro on image optimization, sitemap, content collections, i18n routing, and community extensions — all marketing-page staples. |
| Plain HTML + Tailwind CDN (no build) | Simplest possible; no component reuse, no markdown, no content collections, no per-page SEO tooling. Breaks down at 2+ pages. |
| Separate repo | Adds cross-repo PR overhead with no win for a small OSS project. |
| Cloudflare Pages (vs. GitHub Pages) | Better global CDN TTFB, but one more external account. For an OSS project where "hosted on GitHub Pages" also signals the open-source posture, the delta is not worth the extra service. |

## Decision

Ship the landing as a **standalone Astro 5 + Tailwind v4 + TypeScript** project at `landing/` in the monorepo. Deploy to **GitHub Pages** via a path-filtered GitHub Actions workflow. **Zero runtime coupling** with the Phoenix app.

### Stack

- **Astro 5** (`output: 'static'`) — static HTML, zero JS by default, native i18n routing, native content collections.
- **Tailwind v4** via `@tailwindcss/vite`. No `tailwind.config.js`; customization via `@theme` in CSS.
- **TypeScript** (`strict` preset). Mandatory — the dictionary type is derived from `en.json` and surfaces i18n drift at compile time.
- **`@astrojs/sitemap`** — auto-generated, locale-aware sitemap with `<xhtml:link hreflang>` alternates.
- **`@astrojs/rss`** — one RSS feed per locale.
- **Node 20 LTS** pinned via `landing/.tool-versions` (scoped to the folder; does not add Node to the repo-root `.tool-versions` used by Phoenix devs).

### Isolation

- `.github/workflows/landing.yml` — builds on every PR touching `landing/**`, deploys on push to `main`. Concurrency group `pages`.
- `.github/workflows/ci.yml` — adds `paths-ignore: ['landing/**', '.github/workflows/landing.yml']` on `push` and `pull_request` triggers. Landing-only commits do not burn Elixir CI.
- `landing/` has its own `package.json`, `.gitignore`, `.tool-versions`, `README.md`, `CLAUDE.md`. Nothing leaks outward.
- One-time repo setting: **Settings → Pages → Source: GitHub Actions** (documented; self-correcting if forgotten — the workflow errors loudly).

### Design tokens

CSS custom properties in `landing/src/styles/tokens.css` are a **one-time port** of `assets/css/app.css`. No build-time link; tokens are resynced manually when brand changes land in the admin. Two theme-independent tokens are added that the admin does not have: `--code-bg` and `--code-fg` — always dark, matching the marketing convention for terminal-style code surfaces (in both light and dark pages).

### i18n

- Polish is the default locale. English is an alternate.
- `prefixDefaultLocale: false` — `/` is Polish, `/en/` is English. Clean URLs for the primary audience.
- **All user-visible strings live in `src/i18n/{en,pl}.json`.** Components never hardcode copy — they read via `useTranslations(locale)`. Enforced by convention and documented in `landing/CLAUDE.md`.
- Dictionary type is derived from `en.json`; TypeScript flags any drift between locales at compile time.
- Language switcher preserves the current path when flipping locales (e.g. `/blog/x` → `/en/blog/x`), not just the home.

### Content collections (blog)

- `src/content.config.ts` defines a `blog` collection with Zod-validated frontmatter: `locale`, `title`, `description`, `publishedAt`, `updatedAt?`, `draft`, `tags`, `author`.
- Posts live at `src/content/blog/{locale}/{slug}.md`. Locale is declared in both frontmatter and path.
- `draft: true` excludes a post from the index, RSS, sitemap, and static build — but leaves it reachable in `npm run dev` for preview.
- Per-post SEO: `og:type=article`, `article:published_time`, `article:modified_time`, canonical URL with hreflang alternates, plus `BlogPosting` JSON-LD (headline, date, inLanguage, keywords from tags, author, URL).

### RSS

One feed per locale. `/blog/rss.xml` (PL) and `/en/blog/rss.xml` (EN). Each item emits `<category>` from frontmatter tags and the channel declares `<language>pl-PL>` or `<language>en</language>`. Every page emits a locale-correct `<link rel="alternate" type="application/rss+xml">` in `<head>` for auto-discovery.

### SEO structure

Static HTML + structured data across the surface:

- Per-locale `<html lang>`, `og:locale` + `og:locale:alternate`, canonical URL, hreflang alternates including `x-default`.
- JSON-LD per page: `SoftwareApplication` + `Organization` on every page; `FAQPage` on the home page (FAQ accordion); `BlogPosting` on each blog post.
- Fonts loaded via `preconnect` + `<link rel="stylesheet">` (not CSS `@import`, which would block render twice).
- `apple-touch-icon`, `theme-color` (light + dark variants).
- Polish SEO: the key acronym is expanded once in-copy (`Krajowy System e-Faktur (KSeF)`) and the "2026" obligation year is surfaced in the hero narrative — both are high-volume search signals.

### What goes in the landing vs the admin

- Landing: hero, features, ledger preview, pricing, FAQ, blog, open-source story — all marketing copy and schema.
- Admin: Phoenix LiveView, REST API, sync workers, product workflows.
- The landing's code samples (curl, JSON) are static illustrations and do not hit a live endpoint.

## Consequences

**Good:**

- Free hosting with global CDN caching. Zero infra spend.
- Landing traffic cannot affect Phoenix runtime under any load pattern.
- Marketing changes deploy in under two minutes without touching Elixir CI.
- i18n is first-class from day one. Adding a third locale is a ~20-line diff plus a dictionary.
- Blog posts are plain markdown — reviewable via PR, editable by non-developers.
- SEO surface area (meta, JSON-LD, sitemap, RSS, hreflang) is structurally complete. Content is the only remaining ranking lever.

**Trade-offs accepted:**

- **Second toolchain.** npm/Node lives next to Elixir/OTP in the repo. Tooling diversity up; reviewed and accepted because the payoff (static output, SEO primitives, i18n routing, content collections) is meaningfully higher in Astro than any Elixir SSG.
- **Design-token drift risk.** `tokens.css` is a manual port of `assets/css/app.css`. Brand changes in the admin without a landing follow-up will drift the two surfaces. A build-time link was rejected because it would couple the two projects — the thing we are explicitly avoiding. Mitigated by a header comment in `tokens.css` flagging the port.
- **Component duplication.** HEEx components cannot render in Astro. The landing rebuilds its own atom set (button, card, kbd, tag-pill). Accepted because the visual language divergence is a design requirement.
- **npm optional-dependency bug** for local Apple Silicon (`@rolldown/binding-darwin-arm64`). Fresh clones on new Macs may need `npm install --no-save @rolldown/binding-darwin-arm64`. Documented in `landing/README.md`. CI (Ubuntu) is unaffected.
- **Deploy URL is `appunite.github.io/appunite-ksef-ex/`** until a custom domain lands. `astro.config.mjs` carries `base: '/appunite-ksef-ex'`; drop it and add `public/CNAME` when the domain is ready.

## Implementation pointers

- `landing/CLAUDE.md` — mandatory conventions for future work inside the folder (dictionary-only strings, locale routing invariants, what-NOT-to-do list).
- `landing/README.md` — local dev, build, blog post workflow, RSS mechanics.
- `landing/src/i18n/README.md` — dictionary editing + adding a locale.
- `landing/src/content.config.ts` — blog schema source of truth.
- `.github/workflows/landing.yml` — full build + deploy contract.
