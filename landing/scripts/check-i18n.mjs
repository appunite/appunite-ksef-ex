#!/usr/bin/env node
/**
 * i18n parity check.
 *
 * TypeScript derives the `Dictionary` type from en.json, but missing keys in
 * pl.json only surface at runtime as `undefined` — the JSON is read
 * dynamically, not type-checked per access path. This script walks every key
 * in every locale dictionary and verifies:
 *
 *   - every path present in en.json exists in every other locale
 *   - the value at each path has the same *shape* (string, array, object)
 *   - array lengths match (prevents silently dropping a nav column or FAQ)
 *
 * Exits non-zero with a focused diff when parity breaks.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const dictDir = resolve(here, "../src/i18n");

const base = "en";
const locales = ["pl"];

const load = (name) =>
  JSON.parse(readFileSync(resolve(dictDir, `${name}.json`), "utf8"));

const shapeOf = (v) => {
  if (v === null) return "null";
  if (Array.isArray(v)) return "array";
  return typeof v;
};

const walk = (ref, cmp, path, errors) => {
  const refShape = shapeOf(ref);
  const cmpShape = shapeOf(cmp);

  if (cmp === undefined) {
    errors.push(`missing key: ${path || "<root>"}`);
    return;
  }
  if (refShape !== cmpShape) {
    errors.push(
      `shape mismatch at ${path}: en=${refShape}, other=${cmpShape}`,
    );
    return;
  }
  if (refShape === "array") {
    if (ref.length !== cmp.length) {
      errors.push(
        `array length mismatch at ${path}: en=${ref.length}, other=${cmp.length}`,
      );
    }
    const n = Math.min(ref.length, cmp.length);
    for (let i = 0; i < n; i++) {
      walk(ref[i], cmp[i], `${path}[${i}]`, errors);
    }
    return;
  }
  if (refShape === "object") {
    for (const key of Object.keys(ref)) {
      walk(ref[key], cmp[key], path ? `${path}.${key}` : key, errors);
    }
    for (const key of Object.keys(cmp)) {
      if (!(key in ref)) {
        errors.push(`extra key in other: ${path ? `${path}.${key}` : key}`);
      }
    }
  }
};

const baseDict = load(base);
let failed = false;

for (const locale of locales) {
  const other = load(locale);
  const errors = [];
  walk(baseDict, other, "", errors);
  if (errors.length > 0) {
    failed = true;
    console.error(`\n✗ ${locale}.json has ${errors.length} parity issue(s):`);
    for (const err of errors) console.error(`  - ${err}`);
  } else {
    console.log(`✓ ${locale}.json matches ${base}.json`);
  }
}

if (failed) {
  console.error("\ni18n parity check failed.");
  process.exit(1);
}
