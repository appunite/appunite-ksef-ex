defmodule KsefHub.InvoicesTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice

  setup do
    company = insert(:company)
    %{company: company}
  end

  describe "create_invoice/1" do
    test "creates an invoice with valid attributes", %{company: company} do
      attrs =
        params_for(:invoice,
          ksef_number: "1234567890-20250101-ABC123-01",
          company_id: company.id
        )

      assert {:ok, %Invoice{} = invoice} = Invoices.create_invoice(attrs)
      assert invoice.ksef_number == "1234567890-20250101-ABC123-01"
      assert invoice.type == :income
      assert invoice.status == :pending
      assert invoice.currency == "PLN"
      assert invoice.company_id == company.id
    end

    test "creates xml_file for ksef source invoice", %{company: company} do
      xml = File.read!("test/support/fixtures/sample_income.xml")

      attrs =
        params_for(:invoice, company_id: company.id, xml_content: xml)

      assert {:ok, invoice} = Invoices.create_invoice(attrs)
      assert invoice.xml_file_id
      xml_file = KsefHub.Files.get_file!(invoice.xml_file_id)
      assert xml_file.content == xml
      assert xml_file.content_type == "application/xml"
    end

    test "creates pdf_file for pdf_upload source invoice", %{company: company} do
      pdf_binary = "%PDF-1.4 test content"

      attrs =
        params_for(:pdf_upload_invoice,
          company_id: company.id,
          pdf_content: pdf_binary
        )

      assert {:ok, invoice} = Invoices.create_invoice(attrs)
      assert invoice.pdf_file_id
      pdf_file = KsefHub.Files.get_file!(invoice.pdf_file_id)
      assert pdf_file.content == pdf_binary
      assert pdf_file.content_type == "application/pdf"
    end

    test "returns error with invalid type", %{company: company} do
      attrs = params_for(:invoice, type: :invalid, company_id: company.id)
      assert {:error, changeset} = Invoices.create_invoice(attrs)
      assert "is invalid" in errors_on(changeset).type
    end

    test "returns error without required fields" do
      assert {:error, changeset} = Invoices.create_invoice(%{})
      assert errors_on(changeset).type
      assert errors_on(changeset).seller_nip
      assert errors_on(changeset).invoice_number
      assert errors_on(changeset).company_id
    end

    test "enforces unique (company_id, ksef_number)", %{company: company} do
      insert(:invoice, ksef_number: "dup-1", company: company)
      attrs = params_for(:invoice, ksef_number: "dup-1", company_id: company.id)
      assert {:error, changeset} = Invoices.create_invoice(attrs)
      assert errors_on(changeset).company_id
    end

    test "ksef source requires xml_content", %{company: company} do
      attrs = params_for(:invoice, source: :ksef, xml_content: nil, company_id: company.id)
      assert {:error, changeset} = Invoices.create_invoice(attrs)
      assert errors_on(changeset).xml_content
    end

    test "manual source requires buyer fields and amounts", %{company: company} do
      attrs =
        params_for(:manual_invoice,
          buyer_nip: nil,
          buyer_name: nil,
          net_amount: nil,
          gross_amount: nil,
          company_id: company.id
        )

      assert {:error, changeset} = Invoices.create_invoice(attrs)
      errors = errors_on(changeset)
      assert errors.buyer_nip
      assert errors.buyer_name
      assert errors.net_amount
      assert errors.gross_amount
    end

    test "rejects invalid source", %{company: company} do
      attrs = params_for(:invoice, source: :invalid, company_id: company.id)
      assert {:error, changeset} = Invoices.create_invoice(attrs)
      assert "is invalid" in errors_on(changeset).source
    end
  end

  describe "upsert_invoice/1" do
    test "inserts new invoice and returns :inserted tag", %{company: company} do
      attrs = params_for(:invoice, ksef_number: "upsert-1", company_id: company.id)
      assert {:ok, %Invoice{}, :inserted} = Invoices.upsert_invoice(attrs)
    end

    test "creates xml_file on insert", %{company: company} do
      attrs = params_for(:invoice, ksef_number: "upsert-file-1", company_id: company.id)
      assert {:ok, %Invoice{} = invoice, :inserted} = Invoices.upsert_invoice(attrs)
      assert invoice.xml_file_id
      xml_file = KsefHub.Files.get_file!(invoice.xml_file_id)
      assert xml_file.content_type == "application/xml"
    end

    test "updates existing invoice and returns :updated tag", %{company: company} do
      # Pre-insert with a backdated timestamp so inserted_at != updated_at after upsert
      original =
        insert(:invoice,
          ksef_number: "upsert-2",
          company: company,
          inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
        )

      attrs = params_for(:invoice, ksef_number: "upsert-2", company_id: company.id)

      {:ok, updated, :updated} =
        Invoices.upsert_invoice(%{attrs | seller_name: "Updated Name"})

      assert updated.id == original.id
      assert updated.seller_name == "Updated Name"
    end

    test "preserves prediction fields on re-sync update", %{company: company} do
      original =
        insert(:invoice,
          ksef_number: "upsert-pred",
          company: company,
          type: :expense,
          prediction_status: :predicted,
          prediction_category_name: "finance:invoices",
          prediction_category_confidence: 0.92,
          prediction_tag_name: "monthly",
          prediction_tag_confidence: 0.85,
          prediction_model_version: "v1.0",
          inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
        )

      attrs = params_for(:invoice, ksef_number: "upsert-pred", company_id: company.id)

      {:ok, updated, :updated} =
        Invoices.upsert_invoice(%{attrs | seller_name: "Updated Seller"})

      assert updated.id == original.id
      assert updated.seller_name == "Updated Seller"
      assert updated.prediction_status == :predicted
      assert updated.prediction_category_name == "finance:invoices"
      assert updated.prediction_category_confidence == 0.92
    end
  end

  describe "list_invoices/2" do
    test "returns invoices for the company", %{company: company} do
      insert(:invoice, company: company)
      other = insert(:company)
      insert(:invoice, company: other)

      assert [%Invoice{}] = Invoices.list_invoices(company.id)
    end

    test "filters by type", %{company: company} do
      insert(:invoice, type: :income, company: company)
      insert(:invoice, type: :expense, company: company)

      assert [%{type: :income}] = Invoices.list_invoices(company.id, %{type: :income})
      assert [%{type: :expense}] = Invoices.list_invoices(company.id, %{type: :expense})
    end

    test "filters by status", %{company: company} do
      inv = insert(:invoice, type: :expense, company: company)
      Invoices.approve_invoice(inv)

      assert [%{status: :approved}] = Invoices.list_invoices(company.id, %{status: :approved})
      assert [] = Invoices.list_invoices(company.id, %{status: :rejected})
    end

    test "filters by date range", %{company: company} do
      insert(:invoice, issue_date: ~D[2025-01-01], company: company)
      insert(:invoice, issue_date: ~D[2025-06-15], company: company)

      result =
        Invoices.list_invoices(company.id, %{date_from: ~D[2025-06-01], date_to: ~D[2025-06-30]})

      assert length(result) == 1
    end

    test "filters by seller_nip", %{company: company} do
      insert(:invoice, seller_nip: "1111111111", company: company)
      insert(:invoice, seller_nip: "2222222222", company: company)

      assert [%{seller_nip: "1111111111"}] =
               Invoices.list_invoices(company.id, %{seller_nip: "1111111111"})
    end

    test "searches by query", %{company: company} do
      insert(:invoice, buyer_name: "Acme Corp", company: company)
      insert(:invoice, buyer_name: "Widget Inc", company: company)

      assert [%{buyer_name: "Acme Corp"}] = Invoices.list_invoices(company.id, %{query: "Acme"})
    end

    test "escapes LIKE wildcards in search query", %{company: company} do
      insert(:invoice, buyer_name: "100% Organic", company: company)
      insert(:invoice, buyer_name: "Something Else", company: company)

      assert [%{buyer_name: "100% Organic"}] =
               Invoices.list_invoices(company.id, %{query: "100%"})
    end

    test "escapes underscore wildcards in search query", %{company: company} do
      insert(:invoice, seller_name: "A_B Corp", company: company)
      insert(:invoice, seller_name: "AXB Corp", company: company)

      assert [%{seller_name: "A_B Corp"}] = Invoices.list_invoices(company.id, %{query: "A_B"})
    end

    test "escapes backslash in search query", %{company: company} do
      insert(:invoice, invoice_number: "FV\\2025\\001", company: company)
      insert(:invoice, invoice_number: "FV/2025/002", company: company)

      assert [%{invoice_number: "FV\\2025\\001"}] =
               Invoices.list_invoices(company.id, %{query: "FV\\2025"})
    end

    test "paginates with default page 1 and per_page 25", %{company: company} do
      for i <- 1..30 do
        insert(:invoice,
          company: company,
          invoice_number: "FV/#{String.pad_leading("#{i}", 3, "0")}"
        )
      end

      result = Invoices.list_invoices(company.id)
      assert length(result) == 25
    end

    test "respects page and per_page", %{company: company} do
      for i <- 1..10 do
        insert(:invoice, company: company, issue_date: Date.add(~D[2025-01-01], -i))
      end

      page1 = Invoices.list_invoices(company.id, %{per_page: 3, page: 1})
      page2 = Invoices.list_invoices(company.id, %{per_page: 3, page: 2})

      assert length(page1) == 3
      assert length(page2) == 3

      # Pages should not overlap
      page1_ids = MapSet.new(page1, & &1.id)
      page2_ids = MapSet.new(page2, & &1.id)
      assert MapSet.disjoint?(page1_ids, page2_ids)
    end

    test "caps per_page at 100", %{company: company} do
      for i <- 1..105 do
        insert(:invoice, company: company, invoice_number: "FV/#{i}")
      end

      result = Invoices.list_invoices(company.id, %{per_page: 200})
      assert length(result) == 100
    end

    test "excludes xml_content from list results", %{company: company} do
      insert(:invoice, company: company, xml_content: "<xml>big content</xml>")

      [invoice] = Invoices.list_invoices(company.id)
      assert is_nil(invoice.xml_content)
    end
  end

  describe "count_invoices/2" do
    test "returns count scoped to company", %{company: company} do
      insert(:invoice, company: company)
      insert(:invoice, company: company)
      other = insert(:company)
      insert(:invoice, company: other)

      assert Invoices.count_invoices(company.id) == 2
    end

    test "applies filters to count", %{company: company} do
      insert(:invoice, company: company, type: :income)
      insert(:invoice, company: company, type: :expense)

      assert Invoices.count_invoices(company.id, %{type: :income}) == 1
    end
  end

  describe "list_invoices_paginated/2" do
    test "returns paginated result with metadata", %{company: company} do
      for i <- 1..10 do
        insert(:invoice, company: company, invoice_number: "FV/#{i}")
      end

      result = Invoices.list_invoices_paginated(company.id, %{per_page: 3, page: 2})

      assert length(result.entries) == 3
      assert result.page == 2
      assert result.per_page == 3
      assert result.total_count == 10
      assert result.total_pages == 4
    end

    test "returns total_pages of 1 when no results", %{company: company} do
      result = Invoices.list_invoices_paginated(company.id)

      assert result.entries == []
      assert result.total_count == 0
      assert result.total_pages == 1
    end

    test "preloads category and tags on entries", %{company: company} do
      category = insert(:category, company: company)
      tag = insert(:tag, company: company)
      invoice = insert(:invoice, company: company, category: category)
      insert(:invoice_tag, invoice: invoice, tag: tag)

      result = Invoices.list_invoices_paginated(company.id)

      entry = hd(result.entries)
      assert entry.category.id == category.id
      assert [loaded_tag] = entry.tags
      assert loaded_tag.id == tag.id
    end
  end

  describe "get_invoice_with_details/3" do
    test "returns invoice with preloaded category and tags", %{company: company} do
      category = insert(:category, company: company)
      tag = insert(:tag, company: company)
      invoice = insert(:invoice, company: company, category: category)
      insert(:invoice_tag, invoice: invoice, tag: tag)

      result = Invoices.get_invoice_with_details(company.id, invoice.id)

      assert result.id == invoice.id
      assert result.category.id == category.id
      assert [loaded_tag] = result.tags
      assert loaded_tag.id == tag.id
    end

    test "returns nil when invoice not found", %{company: company} do
      assert is_nil(Invoices.get_invoice_with_details(company.id, Ecto.UUID.generate()))
    end

    test "respects role scoping", %{company: company} do
      income = insert(:invoice, type: :income, company: company)

      assert is_nil(Invoices.get_invoice_with_details(company.id, income.id, role: :reviewer))
    end
  end

  describe "get_invoice!/2" do
    test "returns invoice scoped to company", %{company: company} do
      inv = insert(:invoice, company: company)
      assert %Invoice{} = Invoices.get_invoice!(company.id, inv.id)
    end

    test "raises when invoice belongs to different company", %{company: company} do
      other = insert(:company)
      inv = insert(:invoice, company: other)

      assert_raise Ecto.NoResultsError, fn ->
        Invoices.get_invoice!(company.id, inv.id)
      end
    end
  end

  describe "approve_invoice/1" do
    test "approves an expense invoice", %{company: company} do
      inv = insert(:invoice, type: :expense, company: company)
      assert {:ok, %Invoice{status: :approved}} = Invoices.approve_invoice(inv)
    end

    test "rejects approving an income invoice", %{company: company} do
      inv = insert(:invoice, type: :income, company: company)
      assert {:error, {:invalid_type, :income}} = Invoices.approve_invoice(inv)
    end
  end

  describe "reject_invoice/1" do
    test "rejects an expense invoice", %{company: company} do
      inv = insert(:invoice, type: :expense, company: company)
      assert {:ok, %Invoice{status: :rejected}} = Invoices.reject_invoice(inv)
    end

    test "rejects rejecting an income invoice", %{company: company} do
      inv = insert(:invoice, type: :income, company: company)
      assert {:error, {:invalid_type, :income}} = Invoices.reject_invoice(inv)
    end
  end

  describe "role-based scoping" do
    test "list_invoices_paginated with role: reviewer returns only expense invoices", %{
      company: company
    } do
      insert(:invoice, type: :income, company: company)
      insert(:invoice, type: :expense, company: company)

      result = Invoices.list_invoices_paginated(company.id, %{}, role: :reviewer)

      assert length(result.entries) == 1
      assert hd(result.entries).type == :expense
      assert result.total_count == 1
    end

    test "list_invoices_paginated with role: reviewer overrides user-supplied type: income filter",
         %{company: company} do
      insert(:invoice, type: :income, company: company)
      insert(:invoice, type: :expense, company: company)

      result = Invoices.list_invoices_paginated(company.id, %{type: :income}, role: :reviewer)

      assert length(result.entries) == 1
      assert hd(result.entries).type == :expense
    end

    test "get_invoice with role: reviewer returns nil for income invoice", %{company: company} do
      income = insert(:invoice, type: :income, company: company)

      assert is_nil(Invoices.get_invoice(company.id, income.id, role: :reviewer))
    end

    test "get_invoice with role: reviewer returns expense invoice", %{company: company} do
      expense = insert(:invoice, type: :expense, company: company)

      assert %Invoice{} = Invoices.get_invoice(company.id, expense.id, role: :reviewer)
    end

    test "get_invoice! with role: reviewer raises for income invoice", %{company: company} do
      income = insert(:invoice, type: :income, company: company)

      assert_raise Ecto.NoResultsError, fn ->
        Invoices.get_invoice!(company.id, income.id, role: :reviewer)
      end
    end

    test "list_invoices_paginated with role: owner returns all invoices", %{company: company} do
      insert(:invoice, type: :income, company: company)
      insert(:invoice, type: :expense, company: company)

      result = Invoices.list_invoices_paginated(company.id, %{}, role: :owner)

      assert result.total_count == 2
    end

    test "list_invoices_paginated with role: nil returns all invoices (backward compat)", %{
      company: company
    } do
      insert(:invoice, type: :income, company: company)
      insert(:invoice, type: :expense, company: company)

      result = Invoices.list_invoices_paginated(company.id, %{}, role: nil)

      assert result.total_count == 2
    end

    test "count_invoices with role: reviewer counts only expense invoices", %{company: company} do
      insert(:invoice, type: :income, company: company)
      insert(:invoice, type: :expense, company: company)
      insert(:invoice, type: :expense, company: company)

      assert Invoices.count_invoices(company.id, %{}, role: :reviewer) == 2
    end
  end

  describe "create_manual_invoice/2" do
    test "creates a manual invoice with valid attributes", %{company: company} do
      attrs = %{
        type: :expense,
        seller_nip: "1234567890",
        seller_name: "Seller Sp. z o.o.",
        buyer_nip: "0987654321",
        buyer_name: "Buyer S.A.",
        invoice_number: "FV/2026/001",
        issue_date: ~D[2026-02-20],
        net_amount: Decimal.new("1000.00"),
        gross_amount: Decimal.new("1230.00")
      }

      assert {:ok, %Invoice{} = invoice} = Invoices.create_manual_invoice(company.id, attrs)
      assert invoice.source == :manual
      assert invoice.company_id == company.id
      assert is_nil(invoice.xml_content)
      assert is_nil(invoice.duplicate_of_id)
    end

    test "creates manual invoice with ksef_number (no existing match)", %{company: company} do
      attrs = %{
        type: :expense,
        ksef_number: "manual-ksef-123",
        seller_nip: "1234567890",
        seller_name: "Seller Sp. z o.o.",
        buyer_nip: "0987654321",
        buyer_name: "Buyer S.A.",
        invoice_number: "FV/2026/002",
        issue_date: ~D[2026-02-20],
        net_amount: Decimal.new("1000.00"),
        gross_amount: Decimal.new("1230.00")
      }

      assert {:ok, %Invoice{} = invoice} = Invoices.create_manual_invoice(company.id, attrs)
      assert invoice.ksef_number == "manual-ksef-123"
      assert is_nil(invoice.duplicate_of_id)
    end

    test "auto-detects duplicate when ksef_number matches existing invoice", %{company: company} do
      existing = insert(:invoice, ksef_number: "existing-123", company: company)

      attrs = %{
        type: :expense,
        ksef_number: "existing-123",
        seller_nip: "1234567890",
        seller_name: "Seller Sp. z o.o.",
        buyer_nip: "0987654321",
        buyer_name: "Buyer S.A.",
        invoice_number: "FV/2026/003",
        issue_date: ~D[2026-02-20],
        net_amount: Decimal.new("1000.00"),
        gross_amount: Decimal.new("1230.00")
      }

      assert {:ok, %Invoice{} = invoice} = Invoices.create_manual_invoice(company.id, attrs)
      assert invoice.duplicate_of_id == existing.id
      assert invoice.duplicate_status == :suspected
    end

    test "does not detect duplicate across different companies", %{company: company} do
      other = insert(:company)
      insert(:invoice, ksef_number: "cross-company-123", company: other)

      attrs = %{
        type: :expense,
        ksef_number: "cross-company-123",
        seller_nip: "1234567890",
        seller_name: "Seller Sp. z o.o.",
        buyer_nip: "0987654321",
        buyer_name: "Buyer S.A.",
        invoice_number: "FV/2026/004",
        issue_date: ~D[2026-02-20],
        net_amount: Decimal.new("1000.00"),
        gross_amount: Decimal.new("1230.00")
      }

      assert {:ok, %Invoice{} = invoice} = Invoices.create_manual_invoice(company.id, attrs)
      assert is_nil(invoice.duplicate_of_id)
    end

    test "strips ksef_acquisition_date and permanent_storage_date", %{company: company} do
      attrs = %{
        type: :expense,
        seller_nip: "1234567890",
        seller_name: "Seller Sp. z o.o.",
        buyer_nip: "0987654321",
        buyer_name: "Buyer S.A.",
        invoice_number: "FV/2026/005",
        issue_date: ~D[2026-02-20],
        net_amount: Decimal.new("1000.00"),
        gross_amount: Decimal.new("1230.00"),
        ksef_acquisition_date: DateTime.utc_now(),
        permanent_storage_date: DateTime.utc_now()
      }

      assert {:ok, %Invoice{} = invoice} = Invoices.create_manual_invoice(company.id, attrs)
      assert is_nil(invoice.ksef_acquisition_date)
      assert is_nil(invoice.permanent_storage_date)
    end

    test "creates manual invoice with income type", %{company: company} do
      attrs = %{
        type: :income,
        seller_nip: "1234567890",
        seller_name: "Seller Sp. z o.o.",
        buyer_nip: "0987654321",
        buyer_name: "Buyer S.A.",
        invoice_number: "FV/2026/006",
        issue_date: ~D[2026-02-20],
        net_amount: Decimal.new("1000.00"),
        gross_amount: Decimal.new("1230.00")
      }

      assert {:ok, %Invoice{} = invoice} = Invoices.create_manual_invoice(company.id, attrs)
      assert invoice.type == :income
      assert invoice.source == :manual
    end
  end

  describe "create_pdf_upload_invoice/3" do
    test "creates invoice with complete extraction", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "PDF Seller Sp. z o.o.",
           "buyer_nip" => "0987654321",
           "buyer_name" => "PDF Buyer S.A.",
           "invoice_number" => "FV/PDF/001",
           "issue_date" => "2026-02-20",
           "net_amount" => "1000.00",
           "vat_amount" => "230.00",
           "gross_amount" => "1230.00",
           "currency" => "PLN"
         }}
      end)

      assert {:ok, %Invoice{} = invoice} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{
                 type: :expense,
                 filename: "test.pdf"
               })

      assert invoice.source == :pdf_upload
      assert invoice.extraction_status == :complete
      assert invoice.seller_nip == "1234567890"
      assert invoice.seller_name == "PDF Seller Sp. z o.o."
      assert invoice.invoice_number == "FV/PDF/001"
      assert invoice.issue_date == ~D[2026-02-20]
      assert invoice.net_amount == Decimal.new("1000.00")
      assert invoice.pdf_content == "pdf-data"
      assert invoice.original_filename == "test.pdf"
      assert invoice.pdf_file_id
      pdf_file = KsefHub.Files.get_file!(invoice.pdf_file_id)
      assert pdf_file.content == "pdf-data"
    end

    test "creates invoice with partial extraction when fields missing", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_name" => "Partial Seller",
           "invoice_number" => "FV/PARTIAL/001"
         }}
      end)

      assert {:ok, %Invoice{} = invoice} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{
                 type: :expense,
                 filename: "partial.pdf"
               })

      assert invoice.source == :pdf_upload
      assert invoice.extraction_status == :partial
      assert invoice.seller_name == "Partial Seller"
      assert is_nil(invoice.seller_nip)
      assert is_nil(invoice.issue_date)
    end

    test "creates invoice with failed extraction when service errors", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:error, {:extractor_error, 500}}
      end)

      assert {:ok, %Invoice{} = invoice} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{
                 type: :expense,
                 filename: "failed.pdf"
               })

      assert invoice.source == :pdf_upload
      assert invoice.extraction_status == :failed
      assert is_nil(invoice.seller_nip)
    end

    test "detects duplicates via extracted ksef_number", %{company: company} do
      existing = insert(:invoice, ksef_number: "pdf-dup-123", company: company)

      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "ksef_number" => "pdf-dup-123",
           "seller_nip" => "1234567890",
           "seller_name" => "Seller",
           "invoice_number" => "FV/PDF/DUP",
           "issue_date" => "2026-02-20",
           "net_amount" => "1000.00",
           "gross_amount" => "1230.00"
         }}
      end)

      assert {:ok, %Invoice{} = invoice} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{type: :expense})

      assert invoice.duplicate_of_id == existing.id
      assert invoice.duplicate_status == :suspected
    end

    test "passes context with company info to extraction service", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, opts ->
        context = Keyword.get(opts, :context)
        assert is_binary(context)
        assert context =~ company.name
        assert context =~ company.nip

        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "Seller",
           "invoice_number" => "FV/CTX/001",
           "issue_date" => "2026-02-20",
           "net_amount" => "1000.00",
           "gross_amount" => "1230.00"
         }}
      end)

      assert {:ok, %Invoice{}} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{type: :expense})
    end
  end

  describe "approve_invoice/1 with extraction_status" do
    test "rejects approval of partial-extraction invoice", %{company: company} do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          type: :expense,
          extraction_status: :partial
        )

      assert {:error, :incomplete_extraction} = Invoices.approve_invoice(invoice)
    end

    test "allows approval of complete-extraction invoice", %{company: company} do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          type: :expense,
          extraction_status: :complete
        )

      assert {:ok, %Invoice{status: :approved}} = Invoices.approve_invoice(invoice)
    end

    test "rejects approval of failed-extraction invoice", %{company: company} do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          type: :expense,
          extraction_status: :failed
        )

      assert {:error, :incomplete_extraction} = Invoices.approve_invoice(invoice)
    end

    test "allows approval of invoice with nil extraction_status", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense, extraction_status: nil)

      assert {:ok, %Invoice{status: :approved}} = Invoices.approve_invoice(invoice)
    end
  end

  describe "determine_extraction_status_from_attrs/1" do
    test "returns :complete when all critical fields are present" do
      attrs = %{
        seller_nip: "1234567890",
        seller_name: "Seller",
        invoice_number: "FV/001",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100"),
        gross_amount: Decimal.new("123")
      }

      assert Invoices.determine_extraction_status_from_attrs(attrs) == :complete
    end

    test "returns :partial when net_amount is missing" do
      attrs = %{
        seller_nip: "1234567890",
        seller_name: "Seller",
        invoice_number: "FV/001",
        issue_date: ~D[2026-01-01],
        net_amount: nil,
        gross_amount: Decimal.new("123")
      }

      assert Invoices.determine_extraction_status_from_attrs(attrs) == :partial
    end

    test "returns :partial when gross_amount is missing" do
      attrs = %{
        seller_nip: "1234567890",
        seller_name: "Seller",
        invoice_number: "FV/001",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100"),
        gross_amount: nil
      }

      assert Invoices.determine_extraction_status_from_attrs(attrs) == :partial
    end

    test "returns :partial when seller_nip is missing" do
      attrs = %{
        seller_nip: nil,
        seller_name: "Seller",
        invoice_number: "FV/001",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100"),
        gross_amount: Decimal.new("123")
      }

      assert Invoices.determine_extraction_status_from_attrs(attrs) == :partial
    end

    test "returns :partial when invoice_number is missing" do
      attrs = %{
        seller_nip: "1234567890",
        seller_name: "Seller",
        invoice_number: nil,
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100"),
        gross_amount: Decimal.new("123")
      }

      assert Invoices.determine_extraction_status_from_attrs(attrs) == :partial
    end

    test "treats whitespace-only strings as missing" do
      attrs = %{
        seller_nip: "   ",
        seller_name: "Seller",
        invoice_number: "FV/001",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100"),
        gross_amount: Decimal.new("123")
      }

      assert Invoices.determine_extraction_status_from_attrs(attrs) == :partial
    end
  end

  describe "upsert_invoice/1 sets extraction_status" do
    test "upsert with extraction_status persists the value", %{company: company} do
      attrs =
        params_for(:invoice,
          ksef_number: "es-upsert-1",
          company_id: company.id,
          extraction_status: :complete
        )

      assert {:ok, %Invoice{extraction_status: :complete}, :inserted} =
               Invoices.upsert_invoice(attrs)
    end

    test "upsert updates extraction_status on re-sync", %{company: company} do
      insert(:invoice,
        ksef_number: "es-upsert-2",
        company: company,
        extraction_status: :partial,
        inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
      )

      attrs =
        params_for(:invoice,
          ksef_number: "es-upsert-2",
          company_id: company.id,
          extraction_status: :complete
        )

      assert {:ok, %Invoice{extraction_status: :complete}, :updated} =
               Invoices.upsert_invoice(attrs)
    end
  end

  describe "update_invoice_fields/2" do
    test "updates invoice fields and recalculates extraction_status to complete", %{
      company: company
    } do
      invoice =
        insert(:invoice,
          company: company,
          extraction_status: :partial,
          net_amount: nil,
          gross_amount: nil
        )

      attrs = %{
        "net_amount" => "1000.00",
        "gross_amount" => "1230.00"
      }

      assert {:ok, updated} = Invoices.update_invoice_fields(invoice, attrs)
      assert updated.extraction_status == :complete
      assert Decimal.equal?(updated.net_amount, Decimal.new("1000.00"))
      assert Decimal.equal?(updated.gross_amount, Decimal.new("1230.00"))
    end

    test "keeps extraction_status partial when critical fields still missing", %{
      company: company
    } do
      invoice =
        insert(:invoice,
          company: company,
          extraction_status: :partial,
          seller_nip: nil,
          net_amount: nil,
          gross_amount: nil
        )

      attrs = %{"net_amount" => "1000.00"}

      assert {:ok, updated} = Invoices.update_invoice_fields(invoice, attrs)
      assert updated.extraction_status == :partial
    end

    test "returns error changeset for invalid NIP", %{company: company} do
      invoice = insert(:invoice, company: company)

      attrs = %{"seller_nip" => "abc"}

      assert {:error, changeset} = Invoices.update_invoice_fields(invoice, attrs)
      assert errors_on(changeset).seller_nip
    end
  end

  describe "list_invoices source filter with pdf_upload" do
    test "filters invoices by source=pdf_upload", %{company: company} do
      insert(:invoice, company: company, source: :ksef)
      insert(:pdf_upload_invoice, company: company, source: :pdf_upload)

      results = Invoices.list_invoices(company.id, %{source: :pdf_upload})
      assert length(results) == 1
      assert hd(results).source == :pdf_upload
    end

    test "excludes pdf_content from list results", %{company: company} do
      insert(:pdf_upload_invoice, company: company, pdf_content: "large pdf data")

      [invoice] = Invoices.list_invoices(company.id)
      assert is_nil(invoice.pdf_content)
    end
  end

  describe "create_email_invoice/3" do
    test "creates an expense invoice with source :email", %{company: company} do
      pdf_binary = "%PDF-1.4 fake email content"

      extracted = %{
        "seller_nip" => "1111111111",
        "seller_name" => "Seller Sp. z o.o.",
        "buyer_nip" => company.nip,
        "buyer_name" => "Buyer S.A.",
        "invoice_number" => "FV/2026/001",
        "issue_date" => "2026-02-25",
        "net_amount" => "1000.00",
        "gross_amount" => "1230.00"
      }

      assert {:ok, invoice} =
               Invoices.create_email_invoice(company.id, pdf_binary, extracted,
                 filename: "invoice.pdf"
               )

      assert invoice.source == :email
      assert invoice.type == :expense
      assert invoice.extraction_status == :complete
      assert invoice.seller_nip == "1111111111"
      assert invoice.original_filename == "invoice.pdf"
      assert invoice.pdf_content == pdf_binary
      assert invoice.pdf_file_id
      pdf_file = KsefHub.Files.get_file!(invoice.pdf_file_id)
      assert pdf_file.content == pdf_binary
    end

    test "creates invoice with partial extraction status when fields missing", %{
      company: company
    } do
      pdf_binary = "%PDF-1.4 fake"
      extracted = %{"seller_name" => "Partial Seller"}

      assert {:ok, invoice} =
               Invoices.create_email_invoice(company.id, pdf_binary, extracted, [])

      assert invoice.source == :email
      assert invoice.type == :expense
      assert invoice.extraction_status == :partial
    end

    test "creates invoice with failed extraction status", %{company: company} do
      pdf_binary = "%PDF-1.4 fake"

      assert {:ok, invoice} =
               Invoices.create_email_invoice(company.id, pdf_binary, :extraction_failed,
                 filename: "bad.pdf"
               )

      assert invoice.source == :email
      assert invoice.type == :expense
      assert invoice.extraction_status == :failed
      assert invoice.original_filename == "bad.pdf"
    end
  end

  describe "list_invoices source filter with email" do
    test "filters invoices by source=email", %{company: company} do
      insert(:invoice, company: company, source: :ksef)

      insert(:pdf_upload_invoice,
        company: company,
        source: :email,
        type: :expense
      )

      results = Invoices.list_invoices(company.id, %{source: :email})
      assert length(results) == 1
      assert hd(results).source == :email
    end
  end

  describe "recalculate_extraction_status/2" do
    test "returns complete when all critical fields present", %{company: company} do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :partial,
          seller_nip: "1234567890",
          seller_name: "Seller",
          invoice_number: "FV/001",
          issue_date: ~D[2026-02-20],
          net_amount: Decimal.new("100"),
          gross_amount: Decimal.new("123")
        )

      attrs = %{buyer_name: "Buyer"}
      result = Invoices.recalculate_extraction_status(invoice, attrs)
      assert result[:extraction_status] == :complete
    end

    test "returns partial when critical field is missing", %{company: company} do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :complete,
          seller_nip: "1234567890",
          seller_name: "Seller",
          invoice_number: "FV/001",
          issue_date: ~D[2026-02-20],
          net_amount: Decimal.new("100"),
          gross_amount: Decimal.new("123")
        )

      attrs = %{seller_nip: nil}
      result = Invoices.recalculate_extraction_status(invoice, attrs)
      assert result[:extraction_status] == :partial
    end

    test "treats empty string as missing field", %{company: company} do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :complete,
          seller_nip: "1234567890",
          seller_name: "Seller",
          invoice_number: "FV/001",
          issue_date: ~D[2026-02-20],
          net_amount: Decimal.new("100"),
          gross_amount: Decimal.new("123")
        )

      attrs = %{seller_nip: ""}
      result = Invoices.recalculate_extraction_status(invoice, attrs)
      assert result[:extraction_status] == :partial
    end
  end

  describe "upsert_invoice/1 with manual invoices" do
    test "upsert overrides manual invoice with KSeF data", %{company: company} do
      # Create a manual invoice with a ksef_number (backdate to distinguish insert vs update)
      insert(:manual_invoice,
        ksef_number: "sync-override-1",
        company: company,
        seller_name: "Manual Seller",
        inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
      )

      # Simulate KSeF sync upserting the same ksef_number
      attrs =
        params_for(:invoice,
          ksef_number: "sync-override-1",
          company_id: company.id,
          seller_name: "KSeF Seller"
        )

      assert {:ok, updated, :updated} = Invoices.upsert_invoice(attrs)
      assert updated.seller_name == "KSeF Seller"
      assert updated.source == :ksef
    end
  end

  describe "confirm_duplicate/1" do
    test "confirms a suspected duplicate", %{company: company} do
      original = insert(:invoice, ksef_number: "orig-1", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "orig-1",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      assert {:ok, %Invoice{duplicate_status: :confirmed}} =
               Invoices.confirm_duplicate(duplicate)
    end

    test "returns error for non-duplicate invoice", %{company: company} do
      invoice = insert(:invoice, company: company)
      assert {:error, :not_a_duplicate} = Invoices.confirm_duplicate(invoice)
    end

    test "returns invalid_status when already confirmed", %{company: company} do
      original = insert(:invoice, ksef_number: "orig-c1", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "orig-c1",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :confirmed
        )

      assert {:error, :invalid_status} = Invoices.confirm_duplicate(duplicate)
    end

    test "returns invalid_status when already dismissed", %{company: company} do
      original = insert(:invoice, ksef_number: "orig-c2", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "orig-c2",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :dismissed
        )

      assert {:error, :invalid_status} = Invoices.confirm_duplicate(duplicate)
    end
  end

  describe "dismiss_duplicate/1" do
    test "dismisses a suspected duplicate", %{company: company} do
      original = insert(:invoice, ksef_number: "orig-2", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "orig-2",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      assert {:ok, %Invoice{duplicate_status: :dismissed}} =
               Invoices.dismiss_duplicate(duplicate)
    end

    test "dismisses a confirmed duplicate", %{company: company} do
      original = insert(:invoice, ksef_number: "orig-d1", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "orig-d1",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :confirmed
        )

      assert {:ok, %Invoice{duplicate_status: :dismissed}} =
               Invoices.dismiss_duplicate(duplicate)
    end

    test "returns error for non-duplicate invoice", %{company: company} do
      invoice = insert(:invoice, company: company)
      assert {:error, :not_a_duplicate} = Invoices.dismiss_duplicate(invoice)
    end

    test "returns invalid_status when already dismissed", %{company: company} do
      original = insert(:invoice, ksef_number: "orig-d2", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "orig-d2",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :dismissed
        )

      assert {:error, :invalid_status} = Invoices.dismiss_duplicate(duplicate)
    end
  end

  describe "source filter" do
    test "filters invoices by source", %{company: company} do
      insert(:invoice, company: company, source: :ksef)
      insert(:manual_invoice, company: company, source: :manual)

      ksef_results = Invoices.list_invoices(company.id, %{source: :ksef})
      manual_results = Invoices.list_invoices(company.id, %{source: :manual})

      assert length(ksef_results) == 1
      assert hd(ksef_results).source == :ksef
      assert length(manual_results) == 1
      assert hd(manual_results).source == :manual
    end
  end

  describe "count_by_type_and_status/1" do
    test "returns counts scoped to company", %{company: company} do
      insert(:invoice, type: :income, company: company)
      insert(:invoice, type: :expense, company: company)

      # Invoice in another company should not be counted
      other = insert(:company)
      insert(:invoice, type: :income, company: other)

      counts = Invoices.count_by_type_and_status(company.id)
      assert counts[{:income, :pending}] == 1
      assert counts[{:expense, :pending}] == 1
    end
  end
end
