# Translations

Source of truth for all landing-page copy. Every string in the UI is keyed in these dictionaries — components never hardcode text.

## Files

- `en.json` — English (currently authoritative).
- `pl.json` — Polish. **Stubbed as a copy of `en.json`.** Translate values in-place; keys and structure must stay in sync with `en.json`.
- `index.ts` — exports typed `useTranslations(locale)` + URL helpers.

## Editing

1. Add/change a key in `en.json` first. Keep keys lowercase-camel-case; nest by page section.
2. Mirror the same key in `pl.json`. Never leave a key present in one file and missing in the other — the TypeScript type is derived from `en.json`, so any missing key in `pl.json` becomes a runtime fallback to English.
3. Keep values as plain strings unless the component expects an array/object (see `ledger.bullets`, `api.endpoints`, `footer.cols.*.links`). These are documented in `index.ts` types.

## Polish translation status

All `pl.json` values are English placeholders. Translate them incrementally — the site stays usable throughout because the JSON is valid at every stage.

## Adding a locale

1. Add `src/i18n/{locale}.json` (copy `en.json` as a starting point).
2. Register in `src/i18n/index.ts` → `locales` tuple and `dicts` map.
3. Register in `astro.config.mjs` → `i18n.locales`.
4. Register in the sitemap integration config.
5. Add a route folder `src/pages/{locale}/index.astro`.
6. Add to the `LangSwitcher` component.
