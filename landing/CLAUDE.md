# KSeF Hub — Landing Page

Standalone **Astro 5 + Tailwind v4 + TypeScript** project. Static output, deployed to GitHub Pages via `.github/workflows/landing.yml` on every push to `main` that touches `landing/**`.

**Critical separation:** this project has zero coupling to the Phoenix app in the parent repo.

- Not served by Phoenix, not in the same container, not in the same CI workflow.
- No shared imports, no shared runtime.
- Design tokens in `src/styles/tokens.css` are a **one-time port** of `../assets/css/app.css`; resync manually on brand changes.

When editing files here, follow this document — not the root `CLAUDE.md`, which describes Phoenix conventions that don't apply.

## Tech stack

- **Astro 5** — static output (`output: 'static'`, default)
- **Tailwind v4** — via `@tailwindcss/vite` plugin; Tailwind imports live in `src/styles/global.css` (`@import "tailwindcss";`). Do not reintroduce a `tailwind.config.js` — v4 uses `@theme` in CSS.
- **TypeScript** — Astro default, `strict` preset
- **`@astrojs/sitemap`** — auto-emits sitemap with hreflang alternates
- **Node 20 LTS** — pinned via `.tool-versions` (nodejs 20.18.1)
- **npm**

## Directory structure

```
landing/
├── public/                     # served verbatim (robots.txt, favicon.svg)
├── src/
│   ├── assets/                 # SVGs imported by components
│   ├── components/             # one .astro per page section + shared atoms
│   ├── i18n/
│   │   ├── en.json             # authoritative content dictionary
│   │   ├── pl.json             # Polish (translation pending; currently == en.json)
│   │   ├── index.ts            # useTranslations, getLocaleFromUrl, localizedUrl
│   │   └── README.md
│   ├── layouts/Base.astro      # <html>, <head>, SEO
│   ├── pages/
│   │   ├── index.astro         # Polish (default, no prefix)
│   │   └── en/index.astro      # English
│   └── styles/
│       ├── tokens.css          # design tokens (ported from Phoenix app)
│       └── global.css          # tailwind import + utility classes
├── astro.config.mjs
├── package.json
├── .tool-versions
└── README.md
```

## i18n conventions (non-negotiable)

**Every user-visible string lives in the JSON dictionaries.** No hardcoded text in `.astro` components — not even placeholder copy, not even English-only demo strings. If you find yourself typing literal prose inside a component, stop and add a key to `src/i18n/en.json` first, then mirror it in `pl.json`.

### Adding or changing a string

1. Add the key to `src/i18n/en.json` under the appropriate section.
2. Mirror it in `src/i18n/pl.json` (currently a copy of `en.json` — translation is incremental; keep keys and structure identical).
3. Read it in the component:

   ```astro
   ---
   import { getLocaleFromUrl, useTranslations } from "../i18n";
   const locale = getLocaleFromUrl(Astro.url);
   const t = useTranslations(locale);
   ---
   <p>{t.yourSection.yourKey}</p>
   ```

### Key rules

- Nest by page section: `hero.title`, `features.corrections.body`, `footer.cols.product.heading`.
- camelCase keys.
- Keys are identical across locales. The `Dictionary` type is derived from `en.json`, so TypeScript surfaces drift at compile time.
- Arrays and nested objects are allowed where the component expects them (see `ledger.bullets`, `api.endpoints`, `footer.cols.*.links`). Don't flatten these — the shapes are part of the contract.

### Routing

- Default locale: **Polish** (`pl`). No prefix — `/` is Polish.
- English: `/en/`.
- `prefixDefaultLocale: false` is deliberate. Don't flip it without also updating `localizedUrl`, the sitemap config, and the language switcher together.
- Section anchors (`#features`, `#ledger`, `#api`, `#self-host`) are technical IDs, not translated. Keep them English.

## Writing style

Match the tone of the admin app — dry, technical, infrastructure-grade (Stripe, Linear, Vercel). No marketing voice.

- **No emoji. No exclamation marks.** Not in copy, not in code comments.
- One display weight (600) and one body weight (400).
- `text-wrap: balance` on H1/H2, `text-wrap: pretty` on long paragraphs.
- Teal brand (`--brand`) used sparingly — eyebrow labels, one primary CTA per page, accent dots in diagrams. Everything else is neutral.
- Cards are flat: 1px border, 12px radius, 28px padding, no drop shadow.
- Two button variants only: `.btn-primary` (solid foreground on background) and `.btn-ghost` (border or text). 40px tall.
- Outline-style icons, 1.75px stroke. No stock photography, no gradients.

When introducing new copy, match the specificity of nearby sections. Vague marketing claims (e.g. "enterprise-grade security") are worse than concrete ones ("AES-256-GCM, encrypted at rest"). The `/ksef-hub-design` skill in the parent repo has fuller guidance.

## Design tokens

`src/styles/tokens.css` is a one-time port of `../assets/css/app.css`. All colors, type scale, spacing, and radii live there as CSS custom properties.

- Never invent new colors. Use `var(--brand)`, `var(--foreground)`, `var(--muted-foreground)`, `var(--border)`, `var(--card)`, etc.
- Two themes: light (default) and dark (via `[data-theme="dark"]` on `<html>`). OS preference is respected when `[data-theme]` is unset.
- Two theme-independent tokens for code surfaces: `--code-bg` and `--code-fg`. These stay dark in both themes (marketing convention: code blocks are always "terminal-style"). Do **not** replace them with `--background`/`--foreground` — doing so makes code blocks turn white on dark pages.

When brand tokens change in the admin app, port the delta manually. There is no build-time link.

## Components

Section components live in `src/components/` — one per page section, no props at v1 (they read everything from the dictionary). Shared atoms: `LogoMark.astro`, `GitHubIcon.astro`, `LangSwitcher.astro`, `SEO.astro`.

When adding a new page section:

1. Create `src/components/NewSection.astro`.
2. Add its copy under a new key in `en.json` + mirror in `pl.json`.
3. Import and mount it in `src/pages/index.astro` and `src/pages/en/index.astro` (both files — they're deliberately symmetric).

## Development

```bash
cd landing
npm install
npm run dev                   # http://localhost:4321/appunite-ksef-ex/
npm run build                 # static build → dist/
npm run preview               # serve dist/ locally
```

The dev server runs with HMR; edits to components or JSON dictionaries reflect instantly.

## Deployment

Automatic via `.github/workflows/landing.yml`:

1. Triggers on push to `main` touching `landing/**` (also PRs — build only, no deploy).
2. `npm ci && npm run build` in `landing/`.
3. `actions/upload-pages-artifact@v3` → `actions/deploy-pages@v4`.

One-time manual step per repo (already done, don't redo unless Pages is disabled): **Settings → Pages → Source: GitHub Actions**.

Deployed URL: `https://appunite.github.io/appunite-ksef-ex/` (Polish) and `/en/` (English). The `base: '/appunite-ksef-ex'` in `astro.config.mjs` matches this path; drop it only when a custom domain lands (and update `public/robots.txt` + sitemap URL in the same change).

## What NOT to do

- **Don't hardcode user-visible strings in components.** Dictionary-only.
- **Don't leave keys present in `en.json` but missing in `pl.json`** (or vice versa). TypeScript will flag drift; fix at the source.
- **Don't import from the Phoenix app** (`../lib/...`, `../assets/...` at runtime). The whole point is isolation. The one exception is the manual token resync from `../assets/css/app.css` into `src/styles/tokens.css`, done by hand.
- **Don't add a Tailwind config file.** Tailwind v4 uses `@theme` in CSS.
- **Don't add build-time dependencies on Elixir, Mix, or the Phoenix asset pipeline.** The landing must build with `npm` alone.
- **Don't change the routing strategy** (`prefixDefaultLocale: false`) without updating `localizedUrl`, sitemap config, `LangSwitcher`, and the hreflang emission in `SEO.astro` together.
- **Don't restructure the 11-section layout** (Nav, Hero, TrustStrip, WhyExists, Features, LedgerPreview, ApiSection, OpenSource, Pricing, ClosingCTA, Footer) without a clear reason — the sections were scaffolded deliberately and each maps to a content goal.
- **Don't mix landing and Phoenix changes in one PR.** They deploy independently; the CI workflows are path-filtered.
