import en from "./en.json";
import pl from "./pl.json";

export const defaultLocale = "pl" as const;
export const locales = ["pl", "en"] as const;
export type Locale = (typeof locales)[number];

export type Dictionary = typeof en;

const dicts = {
  en,
  pl,
} satisfies Record<Locale, Dictionary>;

export function isLocale(value: string): value is Locale {
  return (locales as readonly string[]).includes(value);
}

/**
 * Resolve the locale from the current request URL. Matches the routing strategy
 * declared in astro.config.mjs: `/` is the default locale, `/<locale>/...`
 * otherwise.
 */
export function getLocaleFromUrl(url: URL): Locale {
  const base = import.meta.env.BASE_URL;
  const path = url.pathname.startsWith(base)
    ? url.pathname.slice(base.length)
    : url.pathname;
  const first = path.replace(/^\/+/, "").split("/")[0] ?? "";
  return isLocale(first) ? first : defaultLocale;
}

/**
 * Return the current path with both the deploy `base` and any locale prefix
 * stripped — useful for building sibling-locale URLs (e.g. LangSwitcher).
 *
 *   /appunite-ksef-ex/en/blog/abc  →  'blog/abc'
 *   /appunite-ksef-ex/blog/abc     →  'blog/abc'
 *   /appunite-ksef-ex/              →  ''
 */
export function getPathWithoutLocale(url: URL): string {
  const base = import.meta.env.BASE_URL;
  let path = url.pathname.startsWith(base)
    ? url.pathname.slice(base.length)
    : url.pathname;
  path = path.replace(/^\/+/, "").replace(/\/$/, "");
  const first = path.split("/")[0] ?? "";
  if (isLocale(first)) {
    path = path.slice(first.length).replace(/^\/+/, "");
  }
  return path;
}

export function useTranslations(locale: Locale): Dictionary {
  return dicts[locale];
}

/**
 * Build a URL for a given locale, preserving the deploy `base`. The default
 * locale has no prefix (matches Astro's `prefixDefaultLocale: false`).
 */
export function localizedUrl(locale: Locale, path = ""): string {
  const rawBase = import.meta.env.BASE_URL;
  const base = rawBase.endsWith("/") ? rawBase : `${rawBase}/`;
  const trimmed = path.replace(/^\/+/, "");
  if (locale === defaultLocale) return `${base}${trimmed}`;
  return `${base}${locale}/${trimmed}`;
}

export const localeLabels: Record<Locale, string> = {
  pl: "PL",
  en: "EN",
};

export const localeHtmlLang: Record<Locale, string> = {
  pl: "pl-PL",
  en: "en",
};
