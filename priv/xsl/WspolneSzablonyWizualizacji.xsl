<?xml version="1.0" encoding="UTF-8"?>
<!--
  Shared visualization templates for KSeF FA(3) invoices.
  Source: gov.pl - http://crd.gov.pl/wzor/2025/06/25/13775/

  This is a placeholder. Run scripts/update-ksef-stylesheet.sh to fetch
  the actual stylesheet from gov.pl.
-->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <!-- Format a decimal number with 2 decimal places -->
  <xsl:template name="format-amount">
    <xsl:param name="amount"/>
    <xsl:choose>
      <xsl:when test="string-length($amount) > 0">
        <xsl:value-of select="format-number($amount, '#,##0.00')"/>
      </xsl:when>
      <xsl:otherwise>-</xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- Format a date -->
  <xsl:template name="format-date">
    <xsl:param name="date"/>
    <xsl:value-of select="$date"/>
  </xsl:template>

</xsl:stylesheet>
