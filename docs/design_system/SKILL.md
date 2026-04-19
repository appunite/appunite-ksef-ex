---
name: ksef-hub-design
description: Use this skill to generate well-branded interfaces and assets for KSeF Hub (a microservice for Poland's Krajowy System e-Faktur), either for production or throwaway prototypes/mocks/slides. Contains essential design guidelines, colors, type, fonts, assets, and UI kit components for prototyping the Phoenix/LiveView admin and its marketing surfaces.
user-invocable: true
---

# KSeF Hub design skill

Read the `README.md` file within this skill, and explore the other available files.

- `colors_and_type.css` has every design token (shadcn-style custom properties + brand accent, light/dark).
- `brand/` has the working logo (mark + wordmark) and naming alternatives.
- `preview/` has small specimen cards -- good references when building new components.
- `ui_kits/admin/` is a fully-wired LiveView admin recreation: app shell, invoices list, invoice detail, dashboard, settings, login. Read its JSX components (`Primitives.jsx`, `AppShell.jsx`, etc.) -- they are the source of truth for component visuals and API.
- `assets/` holds patterns/icons referenced by the kits (Heroicons is CDN-linked).

If creating visual artifacts (slides, mocks, throwaway prototypes, etc.), copy assets out and create static HTML files for the user to view. Load `colors_and_type.css` from any HTML you produce and everything else will fall into place visually.

If working on production code, read `README.md` to internalize the rules (voice, iconography, status vocabulary, layout) and use the tokens already shipped in `assets/css/app.css` of the real codebase.

If the user invokes this skill without any other guidance, ask them what they want to build or design. Then ask clarifying questions:

- Which surface? (admin UI, marketing landing, docs, slides, one-off mock)
- EN or PL copy?
- Light/dark/both?
- Any specific screens or flows?

Then act as an expert designer who outputs HTML artifacts _or_ production code, depending on the need. Match the existing voice: dry, technical, infrastructure-grade (Stripe/Linear). Never invent new color ramps; always reach for the tokens. Never use emoji except on category badges. Keep the admin flat -- no gradients, no shadows on content cards, borders at 1px.
