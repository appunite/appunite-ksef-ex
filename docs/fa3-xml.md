# FA(3) XML Reference

FA(3) is Poland's structured e-invoice XML format, defined by the Ministry of Finance. This document covers field mappings, XML structure, and parsing gotchas relevant to `lib/ksef_hub/invoices/parser.ex`.

Official schema: http://crd.gov.pl/wzor/2025/06/25/13775/schemat.xsd  
Official stylesheet: http://crd.gov.pl/wzor/2025/06/25/13775/styl.xsl

---

## XML Structure

```xml
<Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
  <Naglowek>            <!-- Header: form code, variant, creation timestamp -->
  <Podmiot1>            <!-- Seller -->
  <Podmiot2>            <!-- Buyer -->
  <Fa>                  <!-- Invoice data: dates, amounts, line items, corrections -->
    <FaWiersz>          <!-- Line item (repeated) -->
```

The parser uses `local-name()` XPath to ignore XML namespaces and `namespace_conformant: true` for robust handling.

---

## Party Structure (`Podmiot1` / `Podmiot2`)

Both seller (`Podmiot1`) and buyer (`Podmiot2`) share the same structure:

| XPath | Domain field | Notes |
|-------|-------------|-------|
| `DaneIdentyfikacyjne/NIP` | `seller_nip` / `buyer_nip` | Tax ID |
| `DaneIdentyfikacyjne/Nazwa` | `seller_name` / `buyer_name` | Company name (preferred) |
| `DaneIdentyfikacyjne/ImiePierwsze` + `Nazwisko` | `seller_name` / `buyer_name` | Personal name fallback |
| `Adres/KodKraju` | `seller_country` / `buyer_country` | ISO country code |
| `Adres/AdresL1` | street portion | Street address |
| `Adres/AdresL2` | postal code + city | Polish format: `"00-001 Warszawa"` |

**Name resolution:** tries `Nazwa` first, falls back to `ImiePierwsze + " " + Nazwisko`.

**Address parsing:** `AdresL2` is parsed with regex `^(\d{2}-\d{3})\s+(.+)$` to split postal code from city. When only `AdresL1` is present, tries pattern `^(.+?),?\s*(\d{2}-\d{3})\s+([^,]+)`. Foreign addresses (no Polish postal code) are stored as-is.

---

## Invoice Header Fields (`Fa` element)

| FA(3) code | Domain field | Type | Notes |
|-----------|-------------|------|-------|
| `P_1` | `issue_date` | `Date` | Invoice issue date |
| `P_2` | `invoice_number` | `String` | Sequential invoice number |
| `P_6` | `sales_date` | `Date` | Sale / service delivery date |
| `P_15` | `gross_amount` | `Decimal` | Total gross amount |
| `KodWaluty` | `currency` | `String` | Defaults to `"PLN"` if absent |
| `RodzajFaktury` | `invoice_kind` | `atom` | See type mapping below |
| `NrZamowienia` | `purchase_order` | `String` | Purchase order number (source 1 of 3) |
| `Platnosc/TerminPlatnosci[1]/Termin` | `due_date` | `Date` | Payment due date (first entry only) |
| `Platnosc/RachunekBankowy[1]/NrRB` | `iban` | `String` | IBAN of first bank account |
| `Platnosc/RachunekBankowy[1]/SWIFT` | `swift_bic` | `String` | SWIFT/BIC of first bank account |
| `Platnosc/RachunekBankowy[1]/NazwaBanku` | `bank_name` | `String` | Bank name of first bank account |

### Invoice type mapping (`RodzajFaktury`)

| FA(3) value | `invoice_kind` atom |
|-------------|---------------------|
| `"VAT"` | `:vat` (default) |
| `"KOR"` | `:correction` |
| `"ZAL"` | `:advance` |
| `"ROZ"` | `:advance_settlement` |
| `"UPR"` | `:simplified` |
| `"KOR_ZAL"` | `:advance_correction` |
| `"KOR_ROZ"` | `:settlement_correction` |

---

## VAT Amount Fields (`Fa` element)

Net amounts are stored in per-rate buckets and summed to produce `net_amount`.

| FA(3) code | VAT rate / category |
|-----------|---------------------|
| `P_13_1` | 23% |
| `P_13_2` | 8% |
| `P_13_3` | 5% |
| `P_13_4` | Taxi flat rate |
| `P_13_5` | Special procedure |
| `P_13_6_1` | 0% domestic (excl. intra-EU & export) |
| `P_13_6_2` | 0% intra-EU delivery |
| `P_13_6_3` | 0% export |
| `P_13_7` | VAT exempt |
| `P_13_8` | Supply outside Poland |
| `P_13_9` | EU services |
| `P_13_10` | Reverse charge |
| `P_13_11` | Margin scheme |

Paired `P_14_X` fields hold the corresponding VAT amounts but are not stored separately. `P_13_X` and `P_14_X` fields sum to `P_15` (gross).

---

## Line Items (`FaWiersz`)

| FA(3) code | Domain field | Type |
|-----------|-------------|------|
| `NrWierszaFa` | `line_number` | `Integer` |
| `P_7` | `description` | `String` |
| `P_8A` | `unit` | `String` |
| `P_8B` | `quantity` | `Decimal` |
| `P_9A` | `unit_price` | `Decimal` |
| `P_11` | `net_amount` | `Decimal` |
| `P_12` | `vat_rate` | `Decimal` |

---

## Correction Invoice Fields (`RodzajFaktury = "KOR"`)

| FA(3) code | Domain field | Notes |
|-----------|-------------|-------|
| `NrFaKorygowanej` | `corrected_invoice_number` | Original invoice number |
| `NrKSeFFaKorygowanej` | `corrected_invoice_ksef_number` | KSeF number of original |
| `DataFaKorygowanej` | `corrected_invoice_date` | Date of original |
| `PrzyczynaKorekty` | `correction_reason` | Free text reason |
| `TypKorekty` | `correction_type` | Integer code |
| `OkresFaKorygowanej/OkresFaKorygowanejOd` | `correction_period_from` | Period start |
| `OkresFaKorygowanej/OkresFaKorygowanejDo` | `correction_period_to` | Period end |

---

## Purchase Order Extraction (3 fallback sources)

The parser tries three sources in order:

1. `Fa/NrZamowienia` — dedicated field (highest priority)
2. `Fa/DodatkowyOpis` — key-value pairs (`Klucz`/`Wartosc`), scanned for `AU_CON_` pattern
3. `Fa/StopkaFaktury` — invoice footer free text, scanned for `AU_CON_` pattern

**Pattern:** `AU_CON_[A-Z0-9]{9}` (case-insensitive, optional `"PO:"` prefix). Result is uppercased. Non-`AU_CON_` purchase order values are silently ignored.

---

## Date Format

All dates use ISO 8601 `YYYY-MM-DD`. The parser calls `Date.from_iso8601/1` and returns `nil` for empty or invalid values (no error raised).

---

## Decimal Parsing

Uses `Decimal.parse/1` for precision. Handles trailing content (e.g., `"0 KR"` in VAT rates). Returns `nil` for empty strings or parse failures.

---

## Test Fixtures

Sample XML files in `test/support/fixtures/`:

| File | Coverage |
|------|----------|
| `sample_income.xml` | Basic income invoice |
| `sample_expense.xml` | Multi-line expense invoice |
| `sample_mixed_vat.xml` | Multiple VAT rates (23%, 8%, 5%) |
| `sample_8pct_vat.xml` | Single 8% VAT rate |
| `sample_margin_scheme.xml` | Margin scheme (P_13_6_1) |
| `sample_income_with_po.xml` | PO in `NrZamowienia` |
| `sample_expense_with_dodatkowy_opis_po.xml` | PO in `DodatkowyOpis` |
| `sample_income_with_iban.xml` | IBAN in `Rachunek` |
| `sample_correction.xml` | Correction invoice (KOR) |
| `sample_address_in_l1_only.xml` | Full address in `AdresL1` only |
| `sample_foreign_address.xml` | Foreign address (no Polish postal code) |
