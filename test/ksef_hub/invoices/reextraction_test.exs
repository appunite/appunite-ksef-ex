defmodule KsefHub.Invoices.ReextractionTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory
  import Mox

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice

  setup :verify_on_exit!

  @sample_xml File.read!("test/support/fixtures/sample_income.xml")
  @sample_xml_with_po File.read!("test/support/fixtures/sample_income_with_po.xml")

  setup do
    company = insert(:company)
    %{company: company}
  end

  describe "reparse_from_stored_xml/2" do
    test "re-parses stored XML and updates invoice fields", %{company: company} do
      attrs =
        params_for(:invoice, company_id: company.id)
        |> Map.put(:xml_content, @sample_xml)

      {:ok, invoice} = Invoices.create_invoice(attrs)
      assert invoice.purchase_order == nil

      # Replace the stored XML file with one that contains a PO number
      xml_file = KsefHub.Files.get_file!(invoice.xml_file_id)
      Ecto.Changeset.change(xml_file, content: @sample_xml_with_po) |> KsefHub.Repo.update!()

      assert {:ok, updated} = Invoices.reparse_from_stored_xml(invoice)
      assert updated.purchase_order == "AU_CON_NW9BBJ4VJ"
    end

    test "preserves invoice type and ksef metadata", %{company: company} do
      attrs =
        params_for(:invoice, company_id: company.id, type: :expense)
        |> Map.put(:xml_content, @sample_xml)

      {:ok, invoice} = Invoices.create_invoice(attrs)

      assert {:ok, updated} = Invoices.reparse_from_stored_xml(invoice)
      assert updated.type == :expense
      assert updated.ksef_number == invoice.ksef_number
      assert updated.ksef_acquisition_date == invoice.ksef_acquisition_date
    end

    test "returns error when invoice has no XML file", %{company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      assert {:error, :no_xml} = Invoices.reparse_from_stored_xml(invoice)
    end

    test "recalculates extraction status", %{company: company} do
      attrs =
        params_for(:invoice, company_id: company.id, extraction_status: :partial)
        |> Map.put(:xml_content, @sample_xml_with_po)

      {:ok, invoice} = Invoices.create_invoice(attrs)

      assert {:ok, updated} = Invoices.reparse_from_stored_xml(invoice)
      assert updated.extraction_status == :complete
    end

    test "backfills billing dates from parsed sales_date", %{company: company} do
      attrs =
        params_for(:invoice,
          company_id: company.id,
          billing_date_from: nil,
          billing_date_to: nil
        )
        |> Map.put(:xml_content, @sample_xml_with_po)

      {:ok, invoice} = Invoices.create_invoice(attrs)
      assert invoice.billing_date_from

      # Clear billing dates to simulate old invoice without them
      invoice
      |> Ecto.Changeset.change(billing_date_from: nil, billing_date_to: nil)
      |> KsefHub.Repo.update!()

      invoice = KsefHub.Repo.get!(Invoice, invoice.id)
      assert invoice.billing_date_from == nil

      assert {:ok, updated} = Invoices.reparse_from_stored_xml(invoice)
      assert updated.billing_date_from != nil
    end
  end

  describe "re_extract_invoice/2" do
    test "re-extracts data from stored PDF and updates invoice", %{company: company} do
      invoice = insert(:pdf_upload_invoice, company: company, extraction_status: :partial)

      KsefHub.InvoiceExtractor.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "5555555555",
           "seller_name" => "Re-extracted Seller",
           "buyer_nip" => company.nip,
           "buyer_name" => "Re-extracted Buyer",
           "invoice_number" => "FV/RE/001",
           "issue_date" => "2026-03-01",
           "net_amount" => "2000.00",
           "gross_amount" => "2460.00"
         }}
      end)

      assert {:ok, updated} = Invoices.re_extract_invoice(invoice, company)
      assert updated.seller_name == "Re-extracted Seller"
      assert updated.invoice_number == "FV/RE/001"
      assert updated.extraction_status == :complete
    end

    test "defaults billing dates from extracted issue_date when not already set", %{
      company: company
    } do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :partial,
          billing_date_from: nil,
          billing_date_to: nil
        )

      KsefHub.InvoiceExtractor.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "5555555555",
           "seller_name" => "Some Seller",
           "invoice_number" => "FV/RE/002",
           "issue_date" => "2026-03-15",
           "net_amount" => "1000.00",
           "gross_amount" => "1230.00"
         }}
      end)

      assert {:ok, updated} = Invoices.re_extract_invoice(invoice, company)
      assert updated.billing_date_from == ~D[2026-03-01]
      assert updated.billing_date_to == ~D[2026-03-01]
    end

    test "returns error when invoice has no PDF", %{company: company} do
      invoice = insert(:invoice, company: company, pdf_file_id: nil)

      assert {:error, :no_pdf} = Invoices.re_extract_invoice(invoice, company)
    end

    test "preserves existing fields when re-extraction returns partial data", %{
      company: company
    } do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :complete,
          seller_name: "Original Seller",
          buyer_name: "Original Buyer",
          invoice_number: "FV/ORIG/001",
          net_amount: Decimal.new("1000.00"),
          gross_amount: Decimal.new("1230.00"),
          iban: "PL61109010140000071219812874"
        )

      KsefHub.InvoiceExtractor.Mock
      |> expect(:extract, fn _pdf, _opts ->
        # Only return seller_name — all other fields missing
        {:ok, %{"seller_name" => "Updated Seller"}}
      end)

      assert {:ok, updated} = Invoices.re_extract_invoice(invoice, company)

      # Updated field should change
      assert updated.seller_name == "Updated Seller"

      # Company-side fields (buyer for expense) are auto-populated from company
      assert updated.buyer_name == company.name
      assert updated.buyer_nip == company.nip

      # Non-company fields should be preserved (not overwritten with nil)
      assert updated.invoice_number == "FV/ORIG/001"
      assert updated.net_amount == Decimal.new("1000.00")
      assert updated.gross_amount == Decimal.new("1230.00")

      # IBAN preserved when extractor omits bank_iban entirely
      assert updated.iban == "PL61109010140000071219812874"

      # Extraction status recalculated from merged invoice state — all critical
      # fields are still present so status stays :complete
      assert updated.extraction_status == :complete
    end

    test "becomes complete when re-extraction fills the missing critical field", %{
      company: company
    } do
      # Invoice is partial because seller_nip is missing
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :partial,
          seller_nip: nil,
          seller_name: "Existing Seller",
          invoice_number: "FV/PART/001",
          issue_date: ~D[2026-03-01],
          net_amount: Decimal.new("500.00"),
          gross_amount: Decimal.new("615.00")
        )

      KsefHub.InvoiceExtractor.Mock
      |> expect(:extract, fn _pdf, _opts ->
        # Re-extract provides the missing seller_nip but not other fields
        {:ok, %{"seller_nip" => "5555555555"}}
      end)

      assert {:ok, updated} = Invoices.re_extract_invoice(invoice, company)

      # Missing field now filled
      assert updated.seller_nip == "5555555555"

      # Existing fields preserved
      assert updated.seller_name == "Existing Seller"
      assert updated.invoice_number == "FV/PART/001"
      assert updated.net_amount == Decimal.new("500.00")

      # Status promoted to complete — merged state has all critical fields
      assert updated.extraction_status == :complete
    end

    test "preserves manually-set billing dates on re-extraction", %{company: company} do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :complete,
          billing_date_from: ~D[2026-01-01],
          billing_date_to: ~D[2026-02-01]
        )

      KsefHub.InvoiceExtractor.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_name" => "New Seller",
           "issue_date" => "2026-05-15"
         }}
      end)

      assert {:ok, updated} = Invoices.re_extract_invoice(invoice, company)
      assert updated.seller_name == "New Seller"
      # Billing dates should NOT be overwritten despite new issue_date
      assert updated.billing_date_from == ~D[2026-01-01]
      assert updated.billing_date_to == ~D[2026-02-01]
    end

    test "returns error when extraction service fails", %{company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      KsefHub.InvoiceExtractor.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:error, {:extractor_error, 500}}
      end)

      assert {:error, {:extractor_error, 500}} =
               Invoices.re_extract_invoice(invoice, company)
    end

    test "rejects re-extraction when buyer NIP doesn't match company", %{company: company} do
      invoice = insert(:pdf_upload_invoice, company: company, extraction_status: :partial)

      KsefHub.InvoiceExtractor.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "5555555555",
           "seller_name" => "Re-extracted Seller",
           "buyer_nip" => "9999999999",
           "invoice_number" => "FV/RE/MISMATCH",
           "issue_date" => "2026-03-01",
           "net_amount" => "2000.00",
           "gross_amount" => "2460.00"
         }}
      end)

      assert {:error, :buyer_nip_mismatch} =
               Invoices.re_extract_invoice(invoice, company)
    end

    test "succeeds when buyer NIP not extracted (fallback to company fields)", %{
      company: company
    } do
      invoice = insert(:pdf_upload_invoice, company: company, extraction_status: :partial)

      KsefHub.InvoiceExtractor.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "5555555555",
           "seller_name" => "Re-extracted Seller",
           "invoice_number" => "FV/RE/NO_NIP",
           "issue_date" => "2026-03-01",
           "net_amount" => "2000.00",
           "gross_amount" => "2460.00"
         }}
      end)

      assert {:ok, updated} = Invoices.re_extract_invoice(invoice, company)
      assert updated.seller_name == "Re-extracted Seller"
      assert updated.buyer_nip == company.nip
      assert updated.buyer_name == company.name
    end

    test "succeeds when buyer NIP has PL prefix matching company", %{company: company} do
      invoice = insert(:pdf_upload_invoice, company: company, extraction_status: :partial)

      KsefHub.InvoiceExtractor.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "5555555555",
           "seller_name" => "Re-extracted Seller",
           "buyer_nip" => "PL#{company.nip}",
           "buyer_name" => "Re-extracted Buyer",
           "invoice_number" => "FV/RE/PL",
           "issue_date" => "2026-03-01",
           "net_amount" => "2000.00",
           "gross_amount" => "2460.00"
         }}
      end)

      assert {:ok, updated} = Invoices.re_extract_invoice(invoice, company)
      assert updated.seller_name == "Re-extracted Seller"
      assert updated.extraction_status == :complete
    end

    test "clears stale iban when re-extraction routes bank_iban to account_number", %{
      company: company
    } do
      # Invoice originally had a valid IBAN from first extraction
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :complete,
          iban: "PL61109010140000071219812874",
          account_number: nil
        )

      # Re-extraction now returns a short non-IBAN value in bank_iban
      KsefHub.InvoiceExtractor.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_name" => "PT Jasa Informasi",
           "buyer_nip" => company.nip,
           "invoice_number" => "1/4/2026",
           "issue_date" => "2026-04-07",
           "net_amount" => "1000.00",
           "gross_amount" => "1000.00",
           "bank_iban" => "167800010537",
           "bank_swift_bic" => "NISPIDJAXXX"
         }}
      end)

      assert {:ok, updated} = Invoices.re_extract_invoice(invoice, company)

      # Stale IBAN must be cleared, not preserved
      assert updated.iban == nil
      # Non-IBAN value routed to account_number
      assert updated.account_number == "167800010537"
      assert updated.swift_bic == "NISPIDJAXXX"
    end

    test "does not clear iban when re-extraction returns IBAN-prefixed short value", %{
      company: company
    } do
      # Invoice has a valid IBAN from first extraction
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :complete,
          iban: "PL61109010140000071219812874",
          account_number: nil
        )

      # Re-extraction returns a truncated IBAN-like value
      KsefHub.InvoiceExtractor.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_name" => "Firma Testowa",
           "buyer_nip" => company.nip,
           "invoice_number" => "FV/2026/01",
           "issue_date" => "2026-04-07",
           "net_amount" => "100.00",
           "gross_amount" => "123.00",
           "bank_iban" => "PL6110901014"
         }}
      end)

      assert {:ok, updated} = Invoices.re_extract_invoice(invoice, company)

      # Existing IBAN must NOT be cleared for IBAN-prefixed short values
      assert updated.iban == "PL61109010140000071219812874"
      # Partial IBAN must NOT be demoted to account_number
      assert updated.account_number == nil
    end

    test "does not clear iban when re-extraction returns formatted IBAN-prefixed short value",
         %{company: company} do
      # Invoice has a valid IBAN from first extraction
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :complete,
          iban: "PL61109010140000071219812874",
          account_number: nil
        )

      # Re-extraction returns a truncated IBAN-like value with spaces/hyphens
      KsefHub.InvoiceExtractor.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_name" => "Firma Testowa",
           "buyer_nip" => company.nip,
           "invoice_number" => "FV/2026/01",
           "issue_date" => "2026-04-07",
           "net_amount" => "100.00",
           "gross_amount" => "123.00",
           "bank_iban" => "PL 6110901014"
         }}
      end)

      assert {:ok, updated} = Invoices.re_extract_invoice(invoice, company)

      # Existing IBAN must NOT be cleared — formatted value is still IBAN-prefixed
      assert updated.iban == "PL61109010140000071219812874"
      assert updated.account_number == nil
    end

    test "detects duplicate after re-extraction populates fields", %{company: company} do
      # KSeF invoice already exists
      _ksef =
        insert(:invoice,
          company: company,
          ksef_number: nil,
          invoice_number: "FV/DUP/RE",
          seller_nip: "5555555555",
          issue_date: ~D[2026-03-01],
          net_amount: Decimal.new("2000.00")
        )

      # Email invoice with failed extraction — no business fields yet
      email_invoice =
        insert(:pdf_upload_invoice,
          company: company,
          source: :email,
          extraction_status: :failed,
          invoice_number: nil,
          seller_nip: nil,
          issue_date: nil,
          net_amount: nil
        )

      assert is_nil(email_invoice.duplicate_of_id)

      # Re-extraction succeeds and populates matching fields
      KsefHub.InvoiceExtractor.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "5555555555",
           "seller_name" => "Seller Sp. z o.o.",
           "buyer_nip" => company.nip,
           "invoice_number" => "FV/DUP/RE",
           "issue_date" => "2026-03-01",
           "net_amount" => "2000.00",
           "gross_amount" => "2460.00"
         }}
      end)

      assert {:ok, updated} = Invoices.re_extract_invoice(email_invoice, company)
      assert updated.duplicate_status == :suspected
      assert updated.duplicate_of_id
    end

    test "does not re-detect duplicate when already marked", %{company: company} do
      original =
        insert(:invoice,
          company: company,
          invoice_number: "FV/ALREADY/DUP",
          seller_nip: "5555555555",
          issue_date: ~D[2026-03-01],
          net_amount: Decimal.new("2000.00")
        )

      # Invoice already marked as duplicate
      email_invoice =
        insert(:pdf_upload_invoice,
          company: company,
          source: :email,
          extraction_status: :partial,
          invoice_number: "FV/ALREADY/DUP",
          seller_nip: "5555555555",
          issue_date: ~D[2026-03-01],
          net_amount: Decimal.new("2000.00"),
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      KsefHub.InvoiceExtractor.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "5555555555",
           "seller_name" => "Updated Seller",
           "invoice_number" => "FV/ALREADY/DUP",
           "issue_date" => "2026-03-01",
           "net_amount" => "2000.00",
           "gross_amount" => "2460.00"
         }}
      end)

      assert {:ok, updated} = Invoices.re_extract_invoice(email_invoice, company)
      # Duplicate info unchanged
      assert updated.duplicate_of_id == original.id
      assert updated.duplicate_status == :suspected
      # But extraction data was still updated
      assert updated.seller_name == "Updated Seller"
    end
  end
end
