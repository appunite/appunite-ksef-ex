#!/usr/bin/env bash
#
# Fetches FA(3) visualization stylesheets from gov.pl and patches import paths
# for local use with xsltproc --nonet.
#
# Usage: ./scripts/update-ksef-stylesheet.sh
#
set -euo pipefail

XSL_DIR="$(cd "$(dirname "$0")/../priv/xsl" && pwd)"
BASE_URL="https://crd.gov.pl/wzor/2025/06/25/13775"
CURL_OPTS="--connect-timeout 10 --max-time 60 -fsSL"

echo "Fetching FA(3) stylesheet from gov.pl..."
curl ${CURL_OPTS} "${BASE_URL}/styl.xsl" -o "${XSL_DIR}/fa3-styl.xsl.tmp"

echo "Extracting shared template URL from stylesheet..."
SHARED_URL=$(grep -oP 'href="\K[^"]*WspolneSzablonyWizualizacji[^"]*' "${XSL_DIR}/fa3-styl.xsl.tmp" || true)
SHARED_FILENAME=$(basename "${SHARED_URL}" 2>/dev/null || echo "")

if [ -n "${SHARED_URL}" ] && [ -n "${SHARED_FILENAME}" ]; then
  echo "Fetching shared templates: ${SHARED_FILENAME}..."
  curl ${CURL_OPTS} "${SHARED_URL}" -o "${XSL_DIR}/${SHARED_FILENAME}"
  echo "  Downloaded ${SHARED_FILENAME}."

  # Extract XSD URLs referenced as xsl:param defaults and download them
  echo "Fetching lookup XSD files..."
  for xsd_url in $(grep -oP "select=\"'\\Khttps?://[^']*\\.xsd" "${XSL_DIR}/${SHARED_FILENAME}" || true); do
    xsd_file=$(basename "${xsd_url}")
    echo "  Downloading ${xsd_file}..."
    if curl --connect-timeout 10 --max-time 30 -fsSL "${xsd_url}" -o "${XSL_DIR}/${xsd_file}" 2>/dev/null; then
      echo "    OK"
    else
      echo "    Failed (creating placeholder)"
      cat > "${XSL_DIR}/${xsd_file}" <<'XSDEOF'
<?xml version="1.0" encoding="UTF-8"?>
<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"/>
XSDEOF
    fi
  done

  # Patch shared template to use local XSD files
  echo "Patching shared template XSD paths..."
  sed -i.bak -E "s|select=\"'https?://[^']*/(Kody[^']*\\.xsd)'|select=\"'\\1'|g" "${XSL_DIR}/${SHARED_FILENAME}"
  rm -f "${XSL_DIR}/${SHARED_FILENAME}.bak"
else
  SHARED_FILENAME="WspolneSzablonyWizualizacji.xsl"
  echo "  Could not extract shared template URL. Keeping existing local copy."
fi

echo "Patching import paths to use local files..."
sed -E \
  "s|href=\"https?://[^\"]*$(echo "${SHARED_FILENAME}" | sed 's/\./\\./g')\"|href=\"${SHARED_FILENAME}\"|g" \
  "${XSL_DIR}/fa3-styl.xsl.tmp" > "${XSL_DIR}/fa3-styl.xsl"

# Add ksef_number param (not in gov stylesheet, injected by our system)
echo "Adding ksef_number parameter..."
sed -i.bak '/<xsl:output/a\
	<xsl:param name="ksef_number" select="'\'''\''"/>
' "${XSL_DIR}/fa3-styl.xsl"
rm -f "${XSL_DIR}/fa3-styl.xsl.bak"

# Add KSeF number display after NaglowekTytulowyKSeF call
sed -i.bak 's|<xsl:call-template name="NaglowekTytulowyKSeF"/>|<xsl:call-template name="NaglowekTytulowyKSeF"/>\
			<xsl:if test="$ksef_number != '\'''\''"><div style="text-align:right; margin-bottom:0.5em; font-size:0.9em;">Numer KSeF: <b><xsl:value-of select="$ksef_number"/></b></div></xsl:if>|' "${XSL_DIR}/fa3-styl.xsl"
rm -f "${XSL_DIR}/fa3-styl.xsl.bak"

echo "Validating stylesheet..."
if command -v xsltproc &>/dev/null; then
  if echo '<root/>' | xsltproc --nonet --noout "${XSL_DIR}/fa3-styl.xsl" - >/dev/null 2>&1; then
    echo "  Stylesheet is valid."
  else
    echo "  WARNING: Stylesheet may have issues. Check manually."
  fi
else
  echo "  xsltproc not installed — skipping validation."
fi

# Clean up temp files
rm -f "${XSL_DIR}/fa3-styl.xsl.tmp" "${XSL_DIR}/fa3-styl.xsl.orig"

echo "Done. Stylesheets updated in ${XSL_DIR}/"
