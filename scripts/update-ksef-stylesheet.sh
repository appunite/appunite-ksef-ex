#!/usr/bin/env bash
#
# Fetches FA(3) visualization stylesheets from gov.pl and patches import paths
# for local use with xsltproc --nonet.
#
# Usage: ./scripts/update-ksef-stylesheet.sh
#
set -euo pipefail

XSL_DIR="$(cd "$(dirname "$0")/../priv/xsl" && pwd)"
BASE_URL="http://crd.gov.pl/wzor/2025/06/25/13775"

echo "Fetching FA(3) stylesheet from gov.pl..."
curl -fsSL "${BASE_URL}/styl.xsl" -o "${XSL_DIR}/fa3-styl.xsl.orig"

echo "Fetching shared templates..."
# The shared templates URL varies by schema version. Try common locations.
if curl -fsSL "${BASE_URL}/WspolneSzablonyWizualizacji.xsl" -o "${XSL_DIR}/WspolneSzablonyWizualizacji.xsl.orig" 2>/dev/null; then
  echo "  Downloaded shared templates."
  cp "${XSL_DIR}/WspolneSzablonyWizualizacji.xsl.orig" "${XSL_DIR}/WspolneSzablonyWizualizacji.xsl"
else
  echo "  Shared templates not found at expected URL. Keeping existing local copy."
fi

echo "Patching import paths to use local files..."
# Replace remote xsl:import/xsl:include hrefs with local filenames
sed -E \
  's|href="https?://[^"]*WspolneSzablonyWizualizacji\.xsl"|href="WspolneSzablonyWizualizacji.xsl"|g' \
  "${XSL_DIR}/fa3-styl.xsl.orig" > "${XSL_DIR}/fa3-styl.xsl"

echo "Validating stylesheet..."
if command -v xsltproc &>/dev/null; then
  # Quick validation: just parse the XSL (--nonet prevents remote fetches)
  if xsltproc --nonet --version "${XSL_DIR}/fa3-styl.xsl" >/dev/null 2>&1; then
    echo "  Stylesheet is valid."
  else
    echo "  WARNING: Stylesheet may have issues. Check manually."
  fi
else
  echo "  xsltproc not installed — skipping validation."
fi

# Clean up originals
rm -f "${XSL_DIR}/fa3-styl.xsl.orig"

echo "Done. Stylesheets updated in ${XSL_DIR}/"
