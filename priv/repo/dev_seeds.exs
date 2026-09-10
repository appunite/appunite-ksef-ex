# Dev seeds for testing correction invoice UI.
# Run with: mix run priv/repo/dev_seeds.exs
#
# Creates correction invoice test data against the SKA company (emil@appunite.com).
# Safe to run multiple times (skips records that already exist).

alias KsefHub.Repo
alias KsefHub.Files.File, as: FileRecord
alias KsefHub.Invoices.Invoice

import Ecto.Query

# SKA — the company emil@appunite.com is a member of
company_id = "cceb30f1-fb4d-4213-9678-b65f69c60d9a"
# An existing SKA expense invoice to link a correction against
existing_expense_id = "705e8975-43c0-4b27-a50c-afa77b1cd062"
existing_expense_number = "0491334514"

correction_xml = File.read!("test/support/fixtures/sample_correction.xml")
income_xml = File.read!("test/support/fixtures/sample_income.xml")

insert_file! = fn content, content_type ->
  Repo.insert!(%FileRecord{content: content, content_type: content_type, filename: nil})
end

# ── 1. Correction (expense) linked to an existing SKA invoice ────────────────
unless Repo.one(
         from i in Invoice,
           where: i.company_id == ^company_id and i.invoice_number == "KOR/2026/SEED-001",
           limit: 1
       ) do
  xml_file = insert_file!.(correction_xml, "application/xml")

  inv = Repo.insert!(%Invoice{
    company_id: company_id,
    type: :expense,
    source: :ksef,
    invoice_kind: :correction,
    seller_nip: "7831812112",
    seller_name: "Appunite S.A.",
    buyer_nip: "7831689686",
    buyer_name: "SKA",
    invoice_number: "KOR/2026/SEED-001",
    issue_date: ~D[2026-04-13],
    billing_date_from: ~D[2026-04-01],
    billing_date_to: ~D[2026-04-30],
    net_amount: Decimal.new("-500.00"),
    gross_amount: Decimal.new("-615.00"),
    currency: "PLN",
    expense_approval_status: :pending,
    corrected_invoice_number: existing_expense_number,
    corrected_invoice_ksef_number: "7831812112-20260409-6018D2000002-8E",
    corrected_invoice_date: ~D[2026-04-01],
    correction_reason: "Błąd rachunkowy lub inna oczywista omyłka",
    correction_type: 1,
    corrects_invoice_id: existing_expense_id,
    xml_file_id: xml_file.id
  })

  IO.puts("Expense correction (linked):   #{inv.invoice_number} (#{inv.id})")
end

# ── 2. Correction (expense) NOT linked to any DB invoice ─────────────────────
unless Repo.one(
         from i in Invoice,
           where: i.company_id == ^company_id and i.invoice_number == "KOR/2026/SEED-002",
           limit: 1
       ) do
  xml_file = insert_file!.(correction_xml, "application/xml")

  inv = Repo.insert!(%Invoice{
    company_id: company_id,
    type: :expense,
    source: :ksef,
    invoice_kind: :correction,
    seller_nip: "9876543210",
    seller_name: "Zumba Fitness LLC",
    buyer_nip: "7831689686",
    buyer_name: "SKA",
    invoice_number: "KOR/2026/SEED-002",
    issue_date: ~D[2026-04-10],
    billing_date_from: ~D[2026-04-01],
    billing_date_to: ~D[2026-04-30],
    net_amount: Decimal.new("-200.00"),
    gross_amount: Decimal.new("-246.00"),
    currency: "PLN",
    expense_approval_status: :pending,
    corrected_invoice_number: "FV/2026/EXTERNAL-999",
    corrected_invoice_ksef_number: "9999999999-20260301-AABBCC000001-ZZ",
    corrected_invoice_date: ~D[2026-03-01],
    correction_reason: "Zmiana stawki VAT",
    correction_type: 2,
    xml_file_id: xml_file.id
  })

  IO.puts("Expense correction (unlinked): #{inv.invoice_number} (#{inv.id})")
end

# ── 3. Correction (expense) with access_restricted ───────────────────────────
unless Repo.one(
         from i in Invoice,
           where: i.company_id == ^company_id and i.invoice_number == "KOR/2026/SEED-003",
           limit: 1
       ) do
  xml_file = insert_file!.(correction_xml, "application/xml")

  inv = Repo.insert!(%Invoice{
    company_id: company_id,
    type: :expense,
    source: :ksef,
    invoice_kind: :correction,
    seller_nip: "1111222233",
    seller_name: "Restricted Corp.",
    buyer_nip: "7831689686",
    buyer_name: "SKA",
    invoice_number: "KOR/2026/SEED-003",
    issue_date: ~D[2026-04-13],
    billing_date_from: ~D[2026-04-01],
    billing_date_to: ~D[2026-04-30],
    net_amount: Decimal.new("-100.00"),
    gross_amount: Decimal.new("-123.00"),
    currency: "PLN",
    expense_approval_status: :pending,
    access_restricted: true,
    corrected_invoice_number: "FV/2026/RESTRICTED-001",
    corrected_invoice_ksef_number: "1111222233-20260101-DEADBEEF0001-AA",
    corrected_invoice_date: ~D[2026-01-01],
    correction_reason: "Korekta danych nabywcy",
    correction_type: 1,
    xml_file_id: xml_file.id
  })

  IO.puts("Expense correction (locked):   #{inv.invoice_number} (#{inv.id})")
end

# ── 4. Original income invoice ────────────────────────────────────────────────
original_income =
  case Repo.one(
         from i in Invoice,
           where: i.company_id == ^company_id and i.invoice_number == "FV/2026/SEED-001",
           limit: 1
       ) do
    nil ->
      xml_file = insert_file!.(income_xml, "application/xml")

      inv = Repo.insert!(%Invoice{
        company_id: company_id,
        type: :income,
        source: :ksef,
        invoice_kind: :vat,
        seller_nip: "7831689686",
        seller_name: "SKA",
        buyer_nip: "5261040828",
        buyer_name: "ALLEGRO Sp. z o.o.",
        invoice_number: "FV/2026/SEED-001",
        issue_date: ~D[2026-04-10],
        billing_date_from: ~D[2026-04-01],
        billing_date_to: ~D[2026-04-30],
        net_amount: Decimal.new("5000.00"),
        gross_amount: Decimal.new("6150.00"),
        currency: "PLN",
        expense_approval_status: :approved,
        xml_file_id: xml_file.id
      })

      IO.puts("Income original:               #{inv.invoice_number} (#{inv.id})")
      inv

    existing ->
      IO.puts("Income original (exists):      #{existing.invoice_number} (#{existing.id})")
      existing
  end

# ── 5. Correction (income) linked to the original above ──────────────────────
unless Repo.one(
         from i in Invoice,
           where: i.company_id == ^company_id and i.invoice_number == "KOR/2026/SEED-004",
           limit: 1
       ) do
  xml_file = insert_file!.(correction_xml, "application/xml")

  inv = Repo.insert!(%Invoice{
    company_id: company_id,
    type: :income,
    source: :ksef,
    invoice_kind: :correction,
    seller_nip: "7831689686",
    seller_name: "SKA",
    buyer_nip: "5261040828",
    buyer_name: "ALLEGRO Sp. z o.o.",
    invoice_number: "KOR/2026/SEED-004",
    issue_date: ~D[2026-04-13],
    billing_date_from: ~D[2026-04-01],
    billing_date_to: ~D[2026-04-30],
    net_amount: Decimal.new("-500.00"),
    gross_amount: Decimal.new("-615.00"),
    currency: "PLN",
    expense_approval_status: :pending,
    corrected_invoice_number: original_income.invoice_number,
    corrected_invoice_ksef_number: "7831689686-20260410-INCOME001-AA",
    corrected_invoice_date: original_income.issue_date,
    correction_reason: "Błąd rachunkowy lub inna oczywista omyłka",
    correction_type: 1,
    corrects_invoice_id: original_income.id,
    xml_file_id: xml_file.id
  })

  IO.puts("Income correction (linked):    #{inv.invoice_number} (#{inv.id})")
end

IO.puts("""

Done! You can now see the test data:
  Expense tab: /c/#{company_id}/invoices
  Income tab:  /c/#{company_id}/invoices?type=income
""")
