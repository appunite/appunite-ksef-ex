# KSeF Hub — landing

Static marketing site for KSeF Hub. Built with [Astro](https://astro.build) 5 + Tailwind v4, deployed to GitHub Pages by `.github/workflows/landing.yml` on every push to `main` that touches `landing/**`.

Zero coupling to the Phoenix app: no shared runtime, no shared container, no cross-imports.

## Develop

```bash
cd landing
npm install
npm run dev
# http://localhost:4321/appunite-ksef-ex/
```

## Build

```bash
npm run build        # -> dist/
npm run preview      # serves dist/ locally
```

## Structure

```
src/
├── assets/                         # SVGs imported by components
├── components/                     # one .astro per page section + shared atoms
├── content/
│   └── blog/
│       ├── pl/                     # Polish posts (*.md)
│       └── en/                     # English posts (*.md)
├── content.config.ts               # Zod schema for the blog collection
├── i18n/
│   ├── en.json                     # authoritative dictionary
│   ├── pl.json                     # Polish translations
│   └── index.ts                    # useTranslations + URL helpers
├── layouts/Base.astro
├── pages/
│   ├── index.astro                 # Polish home (default locale, no prefix)
│   ├── en/index.astro              # English home
│   ├── blog/
│   │   ├── index.astro             # PL blog index
│   │   ├── [...slug].astro         # PL post template
│   │   └── rss.xml.ts              # PL RSS feed endpoint
│   └── en/blog/
│       ├── index.astro             # EN blog index
│       └── rss.xml.ts              # EN RSS feed endpoint
└── styles/
    ├── tokens.css                  # design tokens — ported from ../assets/css/app.css
    └── global.css                  # tailwind import + shared utility classes
public/                             # served verbatim (robots.txt, favicon)
```

## Design tokens

`src/styles/tokens.css` is a one-time port of the admin app's CSS variables in `../assets/css/app.css`. Manually resync when brand tokens change — there is no build-time link.

Light / dark themes both live in the tokens file. Dark mode is triggered by setting `data-theme="dark"` on `<html>`, and follows OS preference by default.

## Deployment

Deployed automatically on push to `main` if `landing/**` changes. The GitHub Actions workflow uses:

1. `actions/setup-node@v4` with `node-version-file: landing/.tool-versions`
2. `npm ci && npm run build` in `landing/`
3. `actions/upload-pages-artifact@v3` + `actions/deploy-pages@v4`

One-time manual step: **Repo → Settings → Pages → Source: GitHub Actions** (only required once per repo).

## Adding a page

1. Drop a new file in `src/pages/`, e.g. `pricing.astro`.
2. Import `Base` layout and section components as usual.
3. `@astrojs/sitemap` picks it up automatically on next build.

## Blog posts

Posts live in `src/content/blog/{locale}/{slug}.md`. The collection schema is declared in `src/content.config.ts` and validated at build time — anything missing or malformed fails the build loudly.

### Add a Polish post

1. Create `src/content/blog/pl/my-slug.md`.
2. Frontmatter contract (required unless noted):

   ```yaml
   ---
   locale: pl                       # must match the folder — schema-validated
   title: "Post title (H1 on the post page)"
   description: "Meta description + blog-index excerpt. 120–160 chars is ideal for SEO."
   publishedAt: 2026-04-20           # ISO date. Sort key on the index.
   updatedAt: 2026-05-02             # optional; renders as "Zaktualizowano: …"
   draft: false                      # optional; defaults to false. true hides from index + feed + build
   tags: ["KSeF", "2026"]           # optional. Shown as pills; piped into RSS categories + BlogPosting keywords.
   author: "KSeF Hub"                # optional; defaults to "KSeF Hub"
   ---
   ```

3. Write the body in markdown. Supported out of the box: headings (`##`, `###`), lists, links, inline `code`, fenced code blocks, `> blockquotes`, horizontal rules (`---`). Styling lives under `.prose` in `src/styles/global.css`.

4. Save. The dev server picks it up via HMR; production build includes it on next run.

### Add an English post

Same process, in `src/content/blog/en/{slug}.md`, with `locale: en`. The EN blog index and RSS feed are already wired — they just need content.

### What happens automatically

- The post appears on the correct-locale blog index (sorted by `publishedAt`, newest first).
- The route is generated: `/blog/{slug}/` (PL) or `/en/blog/{slug}/` (EN) — both with trailing slash.
- The post is added to `sitemap-index.xml` with locale alternates.
- The post is added to the locale's RSS feed (`/blog/rss.xml` or `/en/blog/rss.xml`).
- A `BlogPosting` JSON-LD block is emitted in the post's `<head>` (headline, datePublished, dateModified if set, inLanguage, keywords, author, canonical URL).
- `og:type=article` + `article:published_time` + `article:modified_time` meta tags are emitted.

### Drafts

Set `draft: true` in frontmatter. The post is excluded from the blog index, sitemap, RSS, and static build — but it still renders in `npm run dev` so you can preview it by visiting the URL directly. Flip to `false` when ready to publish.

### Hero image / per-post OG image

Not wired yet. The landing-wide OG fallback (currently the SVG mark) is used for all posts. If you want per-post social previews, add an `ogImage` field to the collection schema in `src/content.config.ts` and surface it in `Base.astro` → `SEO.astro`. Placeholder for a future change.

## RSS feeds

One feed per locale — crawlers, feed readers, and the nav-level auto-discovery all branch on locale.

| Locale | URL                                                       | Source files                                    |
| ------ | --------------------------------------------------------- | ----------------------------------------------- |
| PL     | `https://<site>/blog/rss.xml`                             | `src/pages/blog/rss.xml.ts`                     |
| EN     | `https://<site>/en/blog/rss.xml`                          | `src/pages/en/blog/rss.xml.ts`                  |

Feeds are generated by `@astrojs/rss` at build time. Each item includes: `title`, `link`, `pubDate`, `description`, `categories` (from frontmatter `tags`), and `author`. The feed's `<language>` tag is set per locale (`pl-PL` / `en`).

### Auto-discovery

Every page on the site emits a locale-correct `<link rel="alternate" type="application/rss+xml">` in the `<head>`:

```html
<!-- PL pages -->
<link rel="alternate" type="application/rss+xml" title="KSeF Hub Blog" href="/appunite-ksef-ex/blog/rss.xml">
<!-- EN pages -->
<link rel="alternate" type="application/rss+xml" title="KSeF Hub Blog" href="/appunite-ksef-ex/en/blog/rss.xml">
```

Feed readers pick this up from any page, not just the blog index.

### What you don't need to do

- Regenerate anything. The feed is always a fresh build artifact.
- Update the feed URL if you add posts. Posts are discovered via `getCollection("blog")`.
- Change the locale mapping. The feed already filters by `data.locale` and emits the matching `<language>` tag.

### Known gotcha — local darwin-arm64

On a fresh clone on an Apple Silicon Mac, `npm install` sometimes fails to pull the right `rolldown` native binding (a known npm optional-deps bug). If you see `Cannot find module '@rolldown/binding-darwin-arm64'`, run:

```bash
rm -rf node_modules
npm install
# if still broken:
npm install --no-save @rolldown/binding-darwin-arm64
```

CI (Ubuntu) is unaffected — the `linux-x64-gnu` binding resolves cleanly.
