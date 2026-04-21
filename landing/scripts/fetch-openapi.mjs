#!/usr/bin/env node
// Fetches the OpenAPI spec from the live KSeF Hub API and writes it to
// public/openapi.json so the /api Scalar page can render it at build time.
//
// If the network call fails and a previously fetched copy already exists, we
// keep the old copy and continue the build — this keeps local dev and CI
// retries working when the upstream API is briefly unreachable. If no copy
// exists, we exit non-zero so the missing spec surfaces as a real build error.
import { writeFile, access } from "node:fs/promises";
import { constants } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SPEC_URL =
  process.env.OPENAPI_URL || "https://invoices.appunite.com/api/openapi";
const OUT = resolve(__dirname, "../public/openapi.json");

async function fileExists(path) {
  try {
    await access(path, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

try {
  const res = await fetch(SPEC_URL, { signal: AbortSignal.timeout(30_000) });
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} ${res.statusText}`);
  }
  const spec = await res.json();
  await writeFile(OUT, JSON.stringify(spec, null, 2) + "\n");
  console.log(`[fetch-openapi] ${SPEC_URL} → ${OUT}`);
} catch (err) {
  if (await fileExists(OUT)) {
    console.warn(
      `[fetch-openapi] ${SPEC_URL} unreachable (${err.message}); keeping existing ${OUT}`,
    );
  } else {
    console.error(
      `[fetch-openapi] ${SPEC_URL} unreachable (${err.message}) and no cached spec at ${OUT}`,
    );
    process.exit(1);
  }
}
