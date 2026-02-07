<?xml version="1.0" encoding="UTF-8"?>
<!--
  FA(3) Invoice visualization stylesheet for KSeF.
  Source: gov.pl - http://crd.gov.pl/wzor/2025/06/25/13775/styl.xsl

  This is a placeholder. Run scripts/update-ksef-stylesheet.sh to fetch
  the actual stylesheet from gov.pl. The import path below has been patched
  to reference the local copy instead of the remote URL.
-->
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:fa="http://crd.gov.pl/wzor/2025/06/25/13775/">

  <!-- Patched: local import instead of remote URL -->
  <xsl:import href="WspolneSzablonyWizualizacji.xsl"/>

  <xsl:output method="html" encoding="UTF-8" indent="yes"/>

  <xsl:template match="/">
    <html lang="pl">
      <head>
        <meta charset="UTF-8"/>
        <title>Faktura VAT - <xsl:value-of select="//fa:P_2"/></title>
        <style>
          body { font-family: Arial, sans-serif; margin: 2rem; color: #333; font-size: 14px; }
          h1 { font-size: 1.5rem; border-bottom: 2px solid #333; padding-bottom: 0.5rem; }
          .header-info { margin: 1rem 0; }
          .parties { display: flex; gap: 2rem; margin: 1.5rem 0; }
          .party { flex: 1; padding: 1rem; background: #f5f5f5; border-radius: 4px; }
          .party h3 { margin: 0 0 0.5rem; font-size: 0.85rem; color: #666; text-transform: uppercase; letter-spacing: 0.05em; }
          .party p { margin: 0.25rem 0; }
          table { width: 100%; border-collapse: collapse; margin: 1.5rem 0; }
          th, td { padding: 0.5rem; text-align: left; border-bottom: 1px solid #ddd; }
          th { background: #f0f0f0; font-weight: 600; font-size: 0.85rem; }
          .num { text-align: right; }
          .totals { margin-top: 1.5rem; text-align: right; }
          .totals p { margin: 0.25rem 0; }
          .totals .gross { font-size: 1.2rem; font-weight: bold; }
          .footer { margin-top: 2rem; padding-top: 1rem; border-top: 1px solid #ddd; font-size: 0.8rem; color: #666; }
        </style>
      </head>
      <body>
        <h1>Faktura VAT <xsl:value-of select="//fa:P_2"/></h1>

        <div class="header-info">
          <p>Data wystawienia: <xsl:value-of select="//fa:P_1"/></p>
          <p>Waluta: <xsl:value-of select="//fa:KodWaluty"/></p>
        </div>

        <div class="parties">
          <div class="party">
            <h3>Sprzedawca</h3>
            <p><strong><xsl:value-of select="//fa:Podmiot1//fa:Nazwa"/></strong></p>
            <p>NIP: <xsl:value-of select="//fa:Podmiot1//fa:NIP"/></p>
            <xsl:if test="//fa:Podmiot1//fa:AdresL1">
              <p><xsl:value-of select="//fa:Podmiot1//fa:AdresL1"/></p>
            </xsl:if>
            <xsl:if test="//fa:Podmiot1//fa:AdresL2">
              <p><xsl:value-of select="//fa:Podmiot1//fa:AdresL2"/></p>
            </xsl:if>
          </div>
          <div class="party">
            <h3>Nabywca</h3>
            <p><strong><xsl:value-of select="//fa:Podmiot2//fa:Nazwa"/></strong></p>
            <p>NIP: <xsl:value-of select="//fa:Podmiot2//fa:NIP"/></p>
            <xsl:if test="//fa:Podmiot2//fa:AdresL1">
              <p><xsl:value-of select="//fa:Podmiot2//fa:AdresL1"/></p>
            </xsl:if>
            <xsl:if test="//fa:Podmiot2//fa:AdresL2">
              <p><xsl:value-of select="//fa:Podmiot2//fa:AdresL2"/></p>
            </xsl:if>
          </div>
        </div>

        <table>
          <thead>
            <tr>
              <th>Lp.</th>
              <th>Nazwa towaru/uslugi</th>
              <th>Jm.</th>
              <th class="num">Ilosc</th>
              <th class="num">Cena jed. netto</th>
              <th class="num">Wartosc netto</th>
              <th class="num">Stawka VAT</th>
            </tr>
          </thead>
          <tbody>
            <xsl:for-each select="//fa:FaWiersz">
              <tr>
                <td><xsl:value-of select="fa:NrWierszaFa"/></td>
                <td><xsl:value-of select="fa:P_7"/></td>
                <td><xsl:value-of select="fa:P_8A"/></td>
                <td class="num"><xsl:value-of select="fa:P_8B"/></td>
                <td class="num"><xsl:value-of select="fa:P_9A"/></td>
                <td class="num"><xsl:value-of select="fa:P_11"/></td>
                <td class="num"><xsl:value-of select="fa:P_12"/>%</td>
              </tr>
            </xsl:for-each>
          </tbody>
        </table>

        <div class="totals">
          <p>Razem netto: <xsl:value-of select="//fa:P_13_1"/>&#160;<xsl:value-of select="//fa:KodWaluty"/></p>
          <p>Razem VAT: <xsl:value-of select="//fa:P_14_1"/>&#160;<xsl:value-of select="//fa:KodWaluty"/></p>
          <p class="gross">Razem brutto: <xsl:value-of select="//fa:P_15"/>&#160;<xsl:value-of select="//fa:KodWaluty"/></p>
        </div>

        <div class="footer">
          <p>Dokument wygenerowany z systemu KSeF Hub</p>
        </div>
      </body>
    </html>
  </xsl:template>

</xsl:stylesheet>
