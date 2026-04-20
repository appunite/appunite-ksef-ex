/**
 * Project-wide constants. Single source of truth for URLs and identifiers
 * that live outside the i18n dictionaries (they don't vary per locale).
 *
 * When the repo moves or a custom domain lands, update values here and
 * grep-check the dictionaries for any duplicates that need rotating.
 */

export const repoUrl = "https://github.com/appunite/appunite-ksef-ex";
export const issuesUrl = `${repoUrl}/issues`;
export const releasesUrl = `${repoUrl}/releases`;
export const discussionsUrl = `${repoUrl}/discussions`;

export const contactEmail = "hi@appunite.com";
export const contactMailto = `mailto:${contactEmail}`;
