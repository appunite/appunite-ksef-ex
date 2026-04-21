// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';

// GitHub Pages project site: https://appunite.github.io/appunite-ksef-ex/
// Drop `base` and update `site` when a custom domain lands.
export default defineConfig({
  site: 'https://appunite.github.io',
  base: '/appunite-ksef-ex',
  output: 'static',
  trailingSlash: 'ignore',
  i18n: {
    defaultLocale: 'pl',
    locales: ['pl', 'en'],
    routing: {
      prefixDefaultLocale: false,
    },
  },
  integrations: [
    sitemap({
      i18n: {
        defaultLocale: 'pl',
        locales: {
          pl: 'pl-PL',
          en: 'en',
        },
      },
    }),
  ],
  vite: {
    // Tailwind v4's Vite plugin targets a newer Vite than Astro's bundled Vite,
    // so the Plugin<any> types don't structurally match. Behavior is fine.
    plugins: [/** @type {any} */ (tailwindcss())],
  },
});
