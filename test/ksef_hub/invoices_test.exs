defmodule KsefHub.InvoicesTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory
  import Mox

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice

  setup :verify_on_exit!

  @sample_xml File.read!("test/support/fixtures/sample_income.xml")

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
        |> Map.put(:xml_content, @sample_xml)

      assert {:ok, %Invoice{} = invoice} = Invoices.create_invoice(attrs)
      assert invoice.ksef_number == "1234567890-20250101-ABC123-01"
      assert invoice.type == :income
      assert invoice.expense_approval_status == :pending
      assert invoice.currency == "PLN"
      assert invoice.company_id == company.id
    end

    test "creates xml_file for ksef source invoice", %{company: company} do
      attrs =
        params_for(:invoice, company_id: company.id)
        |> Map.put(:xml_content, @sample_xml)

      assert {:ok, invoice} = Invoices.create_invoice(attrs)
      assert invoice.xml_file_id
      xml_file = KsefHub.Files.get_file!(invoice.xml_file_id)
      assert xml_file.content == @sample_xml
      assert xml_file.content_type == "application/xml"
    end

    test "creates pdf_file for pdf_upload source invoice", %{company: company} do
      pdf_binary = "%PDF-1.4 test content"

      attrs =
        params_for(:pdf_upload_invoice,
          company_id: company.id
        )
        |> Map.put(:pdf_content, pdf_binary)

      assert {:ok, invoice} = Invoices.create_invoice(attrs)
      assert invoice.pdf_file_id
      pdf_file = KsefHub.Files.get_file!(invoice.pdf_file_id)
      assert pdf_file.content == pdf_binary
      assert pdf_file.content_type == "application/pdf"
    end

    test "returns error when file creation fails (content over 10MB)", %{company: company} do
      big_content = :binary.copy(<<0>>, 10_000_001)

      attrs =
        params_for(:pdf_upload_invoice, company_id: company.id)
        |> Map.put(:pdf_content, big_content)

      assert {:error, changeset} = Invoices.create_invoice(attrs)
      assert %{byte_size: ["must be at most 10MB"]} = errors_on(changeset)
    end

    test "returns error with invalid type", %{company: company} do
      attrs =
        params_for(:invoice, type: :invalid, company_id: company.id)
        |> Map.put(:xml_content, @sample_xml)

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

      attrs =
        params_for(:invoice, ksef_number: "dup-1", company_id: company.id)
        |> Map.put(:xml_content, @sample_xml)

      assert {:error, changeset} = Invoices.create_invoice(attrs)
      assert errors_on(changeset).company_id
    end

    test "ksef source requires xml_file_id", %{company: company} do
      attrs = params_for(:invoice, company_id: company.id)
      # params_for doesn't include xml_content, so no file will be created, xml_file_id stays nil
      assert {:error, changeset} = Invoices.create_invoice(attrs)
      assert errors_on(changeset).xml_file_id
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
      attrs =
        params_for(:invoice, source: :invalid, company_id: company.id)
        |> Map.put(:xml_content, @sample_xml)

      assert {:error, changeset} = Invoices.create_invoice(attrs)
      assert "is invalid" in errors_on(changeset).source
    end
  end

  describe "upsert_invoice/1" do
    test "inserts new invoice and returns :inserted tag", %{company: company} do
      attrs =
        params_for(:invoice, ksef_number: "upsert-1", company_id: company.id)
        |> Map.put(:xml_content, @sample_xml)

      assert {:ok, %Invoice{}, :inserted} = Invoices.upsert_invoice(attrs)
    end

    test "creates xml_file on insert", %{company: company} do
      attrs =
        params_for(:invoice, ksef_number: "upsert-file-1", company_id: company.id)
        |> Map.put(:xml_content, @sample_xml)

      assert {:ok, %Invoice{} = invoice, :inserted} = Invoices.upsert_invoice(attrs)
      assert invoice.xml_file_id
      xml_file = KsefHub.Files.get_file!(invoice.xml_file_id)
      assert xml_file.content_type == "application/xml"
    end

    test "creates new xml_file on update, leaving old one as orphan", %{company: company} do
      original =
        insert(:invoice,
          ksef_number: "upsert-orphan",
          company: company,
          inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
        )

      original_file_id = original.xml_file_id

      attrs =
        params_for(:invoice, ksef_number: "upsert-orphan", company_id: company.id)
        |> Map.put(:xml_content, @sample_xml)

      {:ok, updated, :updated} = Invoices.upsert_invoice(attrs)
      assert updated.xml_file_id != original_file_id
      # Old file still exists (harmless orphan)
      assert KsefHub.Files.get_file(original_file_id)
    end

    test "updates existing invoice and returns :updated tag", %{company: company} do
      # Pre-insert with a backdated timestamp so inserted_at != updated_at after upsert
      original =
        insert(:invoice,
          ksef_number: "upsert-2",
          company: company,
          inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
        )

      attrs =
        params_for(:invoice, ksef_number: "upsert-2", company_id: company.id)
        |> Map.put(:xml_content, @sample_xml)

      {:ok, updated, :updated} =
        Invoices.upsert_invoice(%{attrs | seller_name: "Updated Name"})

      assert updated.id == original.id
      assert updated.seller_name == "Updated Name"
    end

    test "marks uploaded invoice as duplicate when ksef sync inserts matching invoice",
         %{company: company} do
      # Simulate a manually uploaded invoice (no ksef_number)
      uploaded =
        insert(:invoice,
          company: company,
          ksef_number: nil,
          source: :pdf_upload,
          invoice_number: "LH-285/04/2026",
          seller_nip: "5260003819",
          issue_date: ~D[2026-04-02],
          net_amount: Decimal.new("3773.38"),
          gross_amount: Decimal.new("3773.38")
        )

      # KSeF sync inserts the same invoice with a ksef_number
      attrs =
        params_for(:invoice,
          ksef_number: "ksef-lh-285",
          company_id: company.id,
          invoice_number: "LH-285/04/2026",
          seller_nip: "5260003819",
          issue_date: ~D[2026-04-02],
          net_amount: Decimal.new("3773.38"),
          gross_amount: Decimal.new("3773.38")
        )
        |> Map.put(:xml_content, @sample_xml)

      # KSeF invoice stays canonical (duplicate_of_id == nil)
      assert {:ok, %Invoice{} = ksef_invoice, :inserted} = Invoices.upsert_invoice(attrs)
      assert is_nil(ksef_invoice.duplicate_of_id)

      # The older uploaded invoice is marked as duplicate of the KSeF one
      updated_uploaded = Repo.get!(Invoice, uploaded.id)
      assert updated_uploaded.duplicate_of_id == ksef_invoice.id
      assert updated_uploaded.duplicate_status == :suspected
    end

    test "upsert does not self-match as duplicate", %{company: company} do
      attrs =
        params_for(:invoice,
          ksef_number: "ksef-no-self-match",
          company_id: company.id,
          invoice_number: "FV/2026/SELF",
          seller_nip: "1234567890",
          issue_date: ~D[2026-04-01]
        )
        |> Map.put(:xml_content, @sample_xml)

      assert {:ok, %Invoice{} = invoice, :inserted} = Invoices.upsert_invoice(attrs)
      assert is_nil(invoice.duplicate_of_id)
    end

    test "preserves prediction fields on re-sync update", %{company: company} do
      original =
        insert(:invoice,
          ksef_number: "upsert-pred",
          company: company,
          type: :expense,
          prediction_status: :predicted,
          prediction_expense_category_name: "finance:invoices",
          prediction_expense_category_confidence: 0.92,
          prediction_expense_tag_name: "monthly",
          prediction_expense_tag_confidence: 0.85,
          prediction_expense_category_model_version: "v1.0",
          prediction_expense_tag_model_version: "v1.0",
          inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
        )

      attrs =
        params_for(:invoice, ksef_number: "upsert-pred", company_id: company.id)
        |> Map.put(:xml_content, @sample_xml)

      {:ok, updated, :updated} =
        Invoices.upsert_invoice(%{attrs | seller_name: "Updated Seller"})

      assert updated.id == original.id
      assert updated.seller_name == "Updated Seller"
      assert updated.prediction_status == :predicted
      assert updated.prediction_expense_category_name == "finance:invoices"
      assert updated.prediction_expense_category_confidence == 0.92

      assert updated.prediction_expense_category_model_version ==
               original.prediction_expense_category_model_version

      assert updated.prediction_expense_tag_model_version ==
               original.prediction_expense_tag_model_version
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

      assert [%{expense_approval_status: :approved}] =
               Invoices.list_invoices(company.id, %{expense_approval_status: :approved})

      assert [] = Invoices.list_invoices(company.id, %{expense_approval_status: :rejected})
    end

    test "excludes confirmed duplicates by default", %{company: company} do
      insert(:invoice, type: :expense, company: company, expense_approval_status: :approved)

      insert(:invoice,
        type: :expense,
        company: company,
        expense_approval_status: :approved,
        duplicate_status: :confirmed
      )

      result = Invoices.list_invoices(company.id, %{statuses: [:approved]})
      assert length(result) == 1
      assert hd(result).duplicate_status != :confirmed
    end

    test "includes confirmed duplicates when duplicate filter is selected", %{company: company} do
      insert(:invoice, type: :expense, company: company, expense_approval_status: :approved)

      insert(:invoice,
        type: :expense,
        company: company,
        expense_approval_status: :approved,
        duplicate_status: :confirmed
      )

      result = Invoices.list_invoices(company.id, %{statuses: [:approved, :duplicate]})
      assert length(result) == 2
    end

    test "shows only duplicates when only duplicate filter is selected", %{company: company} do
      insert(:invoice, type: :expense, company: company, expense_approval_status: :approved)

      insert(:invoice,
        type: :expense,
        company: company,
        expense_approval_status: :approved,
        duplicate_status: :confirmed
      )

      result = Invoices.list_invoices(company.id, %{statuses: [:duplicate]})
      assert length(result) == 1
      assert hd(result).duplicate_status == :confirmed
    end

    test "excludes confirmed duplicates when no statuses filter is applied", %{company: company} do
      insert(:invoice, type: :expense, company: company)

      insert(:invoice,
        type: :expense,
        company: company,
        duplicate_status: :confirmed
      )

      result = Invoices.list_invoices(company.id, %{})
      assert length(result) == 1
      assert is_nil(hd(result).duplicate_status)
    end

    test "excludes confirmed duplicates when explicit statuses filter is an empty list", %{
      company: company
    } do
      insert(:invoice, type: :expense, company: company)

      insert(:invoice,
        type: :expense,
        company: company,
        duplicate_status: :confirmed
      )

      result = Invoices.list_invoices(company.id, %{statuses: []})
      assert length(result) == 1
      assert is_nil(hd(result).duplicate_status)
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

    test "does not preload file associations in list results", %{company: company} do
      insert(:invoice, company: company)

      [invoice] = Invoices.list_invoices(company.id)
      assert %Ecto.Association.NotLoaded{} = invoice.xml_file
      assert %Ecto.Association.NotLoaded{} = invoice.pdf_file
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
      _invoice = insert(:invoice, company: company, category: category, tags: ["monthly"])

      result = Invoices.list_invoices_paginated(company.id)

      entry = hd(result.entries)
      assert entry.category.id == category.id
      assert entry.tags == ["monthly"]
    end
  end

  describe "get_invoice_with_details/3" do
    test "returns invoice with preloaded category and tags", %{company: company} do
      category = insert(:category, company: company)
      invoice = insert(:invoice, company: company, category: category, tags: ["monthly"])

      result = Invoices.get_invoice_with_details(company.id, invoice.id)

      assert result.id == invoice.id
      assert result.category.id == category.id
      assert result.tags == ["monthly"]
    end

    test "returns nil when invoice not found", %{company: company} do
      assert is_nil(Invoices.get_invoice_with_details(company.id, Ecto.UUID.generate()))
    end

    test "respects access control scoping", %{company: company} do
      reviewer = insert(:user)
      insert(:membership, user: reviewer, company: company, role: :reviewer)
      income = insert(:invoice, type: :income, company: company, access_restricted: true)

      assert is_nil(
               Invoices.get_invoice_with_details(company.id, income.id,
                 role: :reviewer,
                 user_id: reviewer.id
               )
             )
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
      assert {:ok, %Invoice{expense_approval_status: :approved}} = Invoices.approve_invoice(inv)
    end

    test "rejects approving an income invoice", %{company: company} do
      inv = insert(:invoice, type: :income, company: company)
      assert {:error, {:invalid_type, :income}} = Invoices.approve_invoice(inv)
    end
  end

  describe "reject_invoice/1" do
    test "rejects an expense invoice", %{company: company} do
      inv = insert(:invoice, type: :expense, company: company)
      assert {:ok, %Invoice{expense_approval_status: :rejected}} = Invoices.reject_invoice(inv)
    end

    test "rejects rejecting an income invoice", %{company: company} do
      inv = insert(:invoice, type: :income, company: company)
      assert {:error, {:invalid_type, :income}} = Invoices.reject_invoice(inv)
    end
  end

  describe "reset_invoice_status/1" do
    test "resets approved expense invoice to pending", %{company: company} do
      inv = insert(:invoice, type: :expense, expense_approval_status: :approved, company: company)

      assert {:ok, %Invoice{expense_approval_status: :pending}} =
               Invoices.reset_invoice_status(inv)
    end

    test "resets rejected expense invoice to pending", %{company: company} do
      inv = insert(:invoice, type: :expense, expense_approval_status: :rejected, company: company)

      assert {:ok, %Invoice{expense_approval_status: :pending}} =
               Invoices.reset_invoice_status(inv)
    end

    test "returns error for already pending invoice", %{company: company} do
      inv = insert(:invoice, type: :expense, expense_approval_status: :pending, company: company)
      assert {:error, :already_pending} = Invoices.reset_invoice_status(inv)
    end

    test "returns error for income invoice", %{company: company} do
      inv = insert(:invoice, type: :income, company: company)
      assert {:error, {:invalid_type, :income}} = Invoices.reset_invoice_status(inv)
    end
  end

  describe "exclude_invoice/1" do
    test "marks an invoice as excluded", %{company: company} do
      inv = insert(:invoice, company: company)
      assert {:ok, %Invoice{is_excluded: true}} = Invoices.exclude_invoice(inv)
    end
  end

  describe "include_invoice/1" do
    test "marks an excluded invoice as included", %{company: company} do
      inv = insert(:invoice, company: company, is_excluded: true)
      assert {:ok, %Invoice{is_excluded: false}} = Invoices.include_invoice(inv)
    end
  end

  describe "create_manual_invoice/2" do
    defp manual_attrs(overrides \\ []) do
      %{
        type: :expense,
        seller_nip: Keyword.get(overrides, :seller_nip, "1234567890"),
        seller_name: "Seller Sp. z o.o.",
        buyer_nip: "0987654321",
        buyer_name: "Buyer S.A.",
        invoice_number: Keyword.get(overrides, :invoice_number, "FV/2026/TEST"),
        issue_date: Keyword.get(overrides, :issue_date, ~D[2026-02-20]),
        net_amount: Keyword.get(overrides, :net_amount, Decimal.new("1000.00")),
        gross_amount: Keyword.get(overrides, :gross_amount, Decimal.new("1230.00"))
      }
      |> then(fn attrs ->
        case Keyword.fetch(overrides, :ksef_number) do
          {:ok, val} -> Map.put(attrs, :ksef_number, val)
          :error -> attrs
        end
      end)
    end

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

    # ── Step 1: same KSeF number ─────────────────────────────────────

    test "duplicate: same KSeF number in same company", %{company: company} do
      existing = insert(:invoice, ksef_number: "KSEF-123", company: company)

      attrs =
        manual_attrs(
          ksef_number: "KSEF-123",
          invoice_number: "FV/001",
          issue_date: ~D[2026-02-20]
        )

      assert {:ok, inv} = Invoices.create_manual_invoice(company.id, attrs)
      assert inv.duplicate_of_id == existing.id
      assert inv.duplicate_status == :suspected
    end

    test "not duplicate: same KSeF number in different company", %{company: company} do
      other = insert(:company)
      insert(:invoice, ksef_number: "KSEF-123", company: other)

      attrs =
        manual_attrs(
          ksef_number: "KSEF-123",
          invoice_number: "FV/001",
          issue_date: ~D[2026-02-20]
        )

      assert {:ok, inv} = Invoices.create_manual_invoice(company.id, attrs)
      assert is_nil(inv.duplicate_of_id)
    end

    test "KSeF number match takes precedence over business field match", %{company: company} do
      ksef_original =
        insert(:invoice,
          company: company,
          ksef_number: "KSEF-PRIORITY",
          invoice_number: "FV/400",
          seller_nip: "5555555555",
          issue_date: ~D[2026-03-25]
        )

      # Another invoice with same business fields but no KSeF number
      insert(:invoice,
        company: company,
        ksef_number: nil,
        invoice_number: "FV/400",
        seller_nip: "5555555555",
        issue_date: ~D[2026-03-25]
      )

      attrs =
        manual_attrs(
          ksef_number: "KSEF-PRIORITY",
          invoice_number: "FV/400",
          seller_nip: "5555555555",
          issue_date: ~D[2026-03-25]
        )

      assert {:ok, inv} = Invoices.create_manual_invoice(company.id, attrs)
      assert inv.duplicate_of_id == ksef_original.id
    end

    # ── Step 2: different KSeF numbers = different invoices ───────────

    test "not duplicate: both have different KSeF numbers despite matching business fields", %{
      company: company
    } do
      insert(:invoice,
        company: company,
        ksef_number: "KSEF-AAA",
        invoice_number: "1/04/2026",
        seller_nip: "1111111111",
        issue_date: ~D[2026-04-08],
        net_amount: Decimal.new("18000.00")
      )

      attrs =
        manual_attrs(
          ksef_number: "KSEF-BBB",
          invoice_number: "1/04/2026",
          seller_nip: "1111111111",
          issue_date: ~D[2026-04-08],
          net_amount: Decimal.new("18000.00")
        )

      assert {:ok, inv} = Invoices.create_manual_invoice(company.id, attrs)
      assert is_nil(inv.duplicate_of_id)
    end

    # ── Step 3a: cross-source (KSeF + email/PDF without KSeF number) ─

    test "duplicate: KSeF invoice added, manual invoice already exists without KSeF number", %{
      company: company
    } do
      manual =
        insert(:invoice,
          company: company,
          ksef_number: nil,
          invoice_number: "FV/500",
          seller_nip: "5555555555",
          issue_date: ~D[2026-03-20],
          net_amount: Decimal.new("3000.00")
        )

      attrs =
        manual_attrs(
          ksef_number: "KSEF-CROSS",
          invoice_number: "FV/500",
          seller_nip: "5555555555",
          issue_date: ~D[2026-03-20],
          net_amount: Decimal.new("3000.00")
        )

      assert {:ok, inv} = Invoices.create_manual_invoice(company.id, attrs)
      assert inv.duplicate_of_id == manual.id
      assert inv.duplicate_status == :suspected
    end

    test "duplicate: manual invoice added, KSeF invoice already exists", %{company: company} do
      ksef =
        insert(:invoice,
          company: company,
          ksef_number: "KSEF-EXISTING",
          invoice_number: "FV/600",
          seller_nip: "5555555555",
          issue_date: ~D[2026-03-20],
          net_amount: Decimal.new("3000.00")
        )

      attrs =
        manual_attrs(
          invoice_number: "FV/600",
          seller_nip: "5555555555",
          issue_date: ~D[2026-03-20],
          net_amount: Decimal.new("3000.00")
        )

      assert {:ok, inv} = Invoices.create_manual_invoice(company.id, attrs)
      assert inv.duplicate_of_id == ksef.id
      assert inv.duplicate_status == :suspected
    end

    # ── Step 3b: two manual EU invoices (both without KSeF, with NIP) ─

    test "duplicate: same invoice_number + issue_date + seller_nip + net_amount, no KSeF", %{
      company: company
    } do
      existing =
        insert(:invoice,
          company: company,
          invoice_number: "FV/100",
          seller_nip: "5555555555",
          issue_date: ~D[2026-03-15],
          net_amount: Decimal.new("2000.00")
        )

      attrs =
        manual_attrs(
          invoice_number: "FV/100",
          seller_nip: "5555555555",
          issue_date: ~D[2026-03-15],
          net_amount: Decimal.new("2000.00")
        )

      assert {:ok, inv} = Invoices.create_manual_invoice(company.id, attrs)
      assert inv.duplicate_of_id == existing.id
      assert inv.duplicate_status == :suspected
    end

    test "not duplicate: same fields but different seller_nip (different EU sellers)", %{
      company: company
    } do
      insert(:invoice,
        company: company,
        invoice_number: "FV/200",
        seller_nip: "1111111111",
        issue_date: ~D[2026-03-20],
        net_amount: Decimal.new("3000.00")
      )

      attrs =
        manual_attrs(
          invoice_number: "FV/200",
          seller_nip: "2222222222",
          issue_date: ~D[2026-03-20],
          net_amount: Decimal.new("3000.00")
        )

      assert {:ok, inv} = Invoices.create_manual_invoice(company.id, attrs)
      assert is_nil(inv.duplicate_of_id)
    end

    # ── Step 3c: two manual non-EU invoices (no NIP) ─────────────────

    # Step 3c (non-EU invoices without NIP) is tested in
    # "create_pdf_upload_invoice/3" — manual source requires seller_nip.

    # ── Step 4: skip detection when fields are missing ───────────────

    test "not duplicate: only invoice_number matches (different date, nip, amount)", %{
      company: company
    } do
      insert(:invoice,
        company: company,
        invoice_number: "FV/300",
        seller_nip: "5555555555",
        issue_date: ~D[2026-03-10]
      )

      attrs =
        manual_attrs(
          invoice_number: "FV/300",
          seller_nip: "9999999999",
          issue_date: ~D[2026-04-10],
          net_amount: Decimal.new("5000.00")
        )

      assert {:ok, inv} = Invoices.create_manual_invoice(company.id, attrs)
      assert is_nil(inv.duplicate_of_id)
    end

    test "skip: blank invoice_number or issue_date aborts detection", %{company: company} do
      insert(:invoice,
        company: company,
        invoice_number: "FV/300",
        seller_nip: "5555555555",
        issue_date: ~D[2026-03-10],
        net_amount: Decimal.new("1000.00")
      )

      base = manual_attrs(seller_nip: "5555555555")

      # Blank issue_date
      attrs = Map.merge(base, %{invoice_number: "FV/300", issue_date: ""})
      assert {:error, _} = Invoices.create_manual_invoice(company.id, attrs)

      # Whitespace-only invoice_number
      attrs = Map.merge(base, %{invoice_number: "   ", issue_date: ~D[2026-03-10]})
      assert {:error, _} = Invoices.create_manual_invoice(company.id, attrs)
    end

    test "skip: missing net_amount is rejected by changeset (never reaches detection)", %{
      company: company
    } do
      insert(:invoice,
        company: company,
        invoice_number: "FV/700",
        seller_nip: "5555555555",
        issue_date: ~D[2026-03-10],
        net_amount: Decimal.new("1000.00")
      )

      attrs =
        manual_attrs(
          invoice_number: "FV/700",
          seller_nip: "5555555555",
          issue_date: ~D[2026-03-10],
          net_amount: nil,
          gross_amount: Decimal.new("1230.00")
        )

      assert {:error, changeset} = Invoices.create_manual_invoice(company.id, attrs)
      assert %{net_amount: ["can't be blank"]} = errors_on(changeset)
    end

    test "strips ksef_acquisition_date and ksef_permanent_storage_date", %{company: company} do
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
        ksef_permanent_storage_date: DateTime.utc_now()
      }

      assert {:ok, %Invoice{} = invoice} = Invoices.create_manual_invoice(company.id, attrs)
      assert is_nil(invoice.ksef_acquisition_date)
      assert is_nil(invoice.ksef_permanent_storage_date)
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

    test "stores created_by_id when provided", %{company: company} do
      user = insert(:user)
      insert(:membership, user: user, company: company, role: :owner)

      attrs = %{
        type: :expense,
        seller_nip: "1234567890",
        seller_name: "Seller Sp. z o.o.",
        buyer_nip: "0987654321",
        buyer_name: "Buyer S.A.",
        invoice_number: "FV/2026/CB1",
        issue_date: ~D[2026-02-20],
        net_amount: Decimal.new("1000.00"),
        gross_amount: Decimal.new("1230.00"),
        created_by_id: user.id
      }

      assert {:ok, %Invoice{} = invoice} = Invoices.create_manual_invoice(company.id, attrs)
      assert invoice.created_by_id == user.id
    end

    test "created_by_id defaults to nil when not provided", %{company: company} do
      attrs = %{
        type: :expense,
        seller_nip: "1234567890",
        seller_name: "Seller Sp. z o.o.",
        buyer_nip: "0987654321",
        buyer_name: "Buyer S.A.",
        invoice_number: "FV/2026/CB2",
        issue_date: ~D[2026-02-20],
        net_amount: Decimal.new("1000.00"),
        gross_amount: Decimal.new("1230.00")
      }

      assert {:ok, %Invoice{} = invoice} = Invoices.create_manual_invoice(company.id, attrs)
      assert is_nil(invoice.created_by_id)
    end
  end

  describe "create_pdf_upload_invoice/3" do
    test "creates invoice with complete extraction", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "PDF Seller Sp. z o.o.",
           "buyer_nip" => company.nip,
           "buyer_name" => "PDF Buyer S.A.",
           "invoice_number" => "FV/PDF/001",
           "issue_date" => "2026-02-20",
           "net_amount" => "1000.00",
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
      existing =
        insert(:invoice, ksef_number: "1234567890-20260220-010080615740-E4", company: company)

      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "ksef_number" => "1234567890-20260220-010080615740-E4",
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

    test "detects duplicate for non-EU invoices without NIP (matches on invoice_number + issue_date + net_amount)",
         %{company: company} do
      existing =
        insert(:invoice,
          company: company,
          source: :pdf_upload,
          invoice_number: "INV-2026-042",
          seller_nip: nil,
          seller_name: "US Corp LLC",
          issue_date: ~D[2026-03-20],
          net_amount: Decimal.new("5000.00")
        )

      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_name" => "US Corp LLC",
           "buyer_nip" => company.nip,
           "buyer_name" => "Buyer S.A.",
           "invoice_number" => "INV-2026-042",
           "issue_date" => "2026-03-20",
           "net_amount" => "5000.00",
           "gross_amount" => "5000.00"
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

    test "stores addresses, dates, and bank details from extraction", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "PDF Seller Sp. z o.o.",
           "buyer_nip" => company.nip,
           "buyer_name" => "PDF Buyer S.A.",
           "invoice_number" => "FV/PDF/ADDR",
           "issue_date" => "2026-02-20",
           "sales_date" => "2026-02-15",
           "due_date" => "2026-03-20",
           "net_amount" => "1000.00",
           "gross_amount" => "1230.00",
           "currency" => "PLN",
           "bank_iban" => "PL61109010140000071219812874",
           "bank_swift_bic" => "BPKOPLPW",
           "bank_name" => "PKO BP",
           "bank_notes" => "Reference: FV/PDF/ADDR",
           "seller_address_street" => "ul. Sprzedawcy 10",
           "seller_address_city" => "Warszawa",
           "seller_address_postal_code" => "00-001",
           "seller_address_country" => "PL",
           "buyer_address_street" => "ul. Kupca 5",
           "buyer_address_city" => "Kraków",
           "buyer_address_postal_code" => "30-002",
           "buyer_address_country" => "PL"
         }}
      end)

      assert {:ok, %Invoice{} = invoice} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{
                 type: :expense,
                 filename: "with_addresses.pdf"
               })

      assert invoice.sales_date == ~D[2026-02-15]
      assert invoice.due_date == ~D[2026-03-20]
      assert invoice.iban == "PL61109010140000071219812874"
      assert invoice.swift_bic == "BPKOPLPW"
      assert invoice.bank_name == "PKO BP"
      assert invoice.payment_instructions == "Reference: FV/PDF/ADDR"

      assert invoice.seller_address["street"] == "ul. Sprzedawcy 10"
      assert invoice.seller_address["postal_code"] == "00-001"
      assert invoice.buyer_address["city"] == "Kraków"
      assert invoice.buyer_address["country"] == "PL"
    end

    test "stores US wire details from extraction", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "US Vendor Inc.",
           "invoice_number" => "INV-US-001",
           "issue_date" => "2026-02-20",
           "net_amount" => "500.00",
           "gross_amount" => "500.00",
           "currency" => "USD",
           "bank_routing_number" => "021000021",
           "bank_account_number" => "123456789012",
           "bank_swift_bic" => "CITIUS33",
           "bank_name" => "JPMorgan Chase"
         }}
      end)

      assert {:ok, %Invoice{} = invoice} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{type: :expense})

      assert invoice.iban == nil
      assert invoice.routing_number == "021000021"
      assert invoice.account_number == "123456789012"
      assert invoice.swift_bic == "CITIUS33"
      assert invoice.bank_name == "JPMorgan Chase"
    end

    test "normalizes IBAN with spaces from extraction", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "Test Seller",
           "invoice_number" => "FV/IBAN/SPACES",
           "issue_date" => "2026-02-20",
           "net_amount" => "100.00",
           "gross_amount" => "123.00",
           "bank_iban" => "PL 61 1090 1014 0000 0712 1981 2874"
         }}
      end)

      assert {:ok, %Invoice{} = invoice} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{type: :expense})

      assert invoice.iban == "PL61109010140000071219812874"
    end

    test "strips spaces from account numbers without country prefix", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "Test Seller",
           "invoice_number" => "FV/IBAN/DOMESTIC",
           "issue_date" => "2026-02-20",
           "net_amount" => "100.00",
           "gross_amount" => "123.00",
           "bank_iban" => "61 1090 1014 0000 0712 1981 2874"
         }}
      end)

      assert {:ok, %Invoice{} = invoice} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{type: :expense})

      assert invoice.iban == "61109010140000071219812874"
    end

    test "routes short non-IBAN account numbers to account_number field", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_name" => "PT Jasa Informasi",
           "invoice_number" => "1/4/2026",
           "issue_date" => "2026-04-07",
           "net_amount" => "1000.00",
           "gross_amount" => "1000.00",
           "bank_iban" => "167800010537",
           "bank_swift_bic" => "NISPIDJAXXX"
         }}
      end)

      assert {:ok, %Invoice{} = invoice} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{type: :expense})

      assert invoice.iban == nil
      assert invoice.account_number == "167800010537"
      assert invoice.swift_bic == "NISPIDJAXXX"
    end

    test "explicit bank_account_number takes priority over non-IBAN fallback", %{
      company: company
    } do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_name" => "Test Seller",
           "invoice_number" => "FV/BANK/001",
           "issue_date" => "2026-04-07",
           "net_amount" => "500.00",
           "gross_amount" => "500.00",
           "bank_iban" => "12345678",
           "bank_account_number" => "9876543210"
         }}
      end)

      assert {:ok, %Invoice{} = invoice} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{type: :expense})

      assert invoice.iban == nil
      assert invoice.account_number == "9876543210"
    end

    test "does not demote IBAN-prefixed short value to account_number", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_name" => "Firma Testowa",
           "invoice_number" => "FV/2026/01",
           "issue_date" => "2026-04-07",
           "net_amount" => "100.00",
           "gross_amount" => "123.00",
           "bank_iban" => "PL6110901014"
         }}
      end)

      assert {:ok, %Invoice{} = invoice} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{type: :expense})

      # Short but IBAN-prefixed: don't treat as local account number
      assert invoice.iban == nil
      assert invoice.account_number == nil
    end

    test "maps flat address and bank keys from extraction schema", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "Flat Schema Seller",
           "buyer_nip" => company.nip,
           "buyer_name" => "Flat Schema Buyer",
           "invoice_number" => "FV/FLAT/001",
           "issue_date" => "2026-03-01",
           "net_amount" => "1000.00",
           "gross_amount" => "1230.00",
           "currency" => "PLN",
           "seller_address_street" => "ul. Testowa 1",
           "seller_address_city" => "Warszawa",
           "seller_address_postal_code" => "00-001",
           "seller_address_country" => "PL",
           "buyer_address_street" => "ul. Kupna 5",
           "buyer_address_city" => "Kraków",
           "buyer_address_postal_code" => "30-002",
           "buyer_address_country" => "PL",
           "bank_iban" => "PL61109010140000071219812874",
           "bank_swift_bic" => "BPKOPLPW",
           "bank_name" => "PKO BP",
           "bank_routing_number" => "",
           "bank_account_number" => "",
           "bank_address" => "ul. Bankowa 1, Warszawa",
           "bank_notes" => "Reference: FV/FLAT/001",
           "purchase_order" => "AU_CON_NW9BBJ4VJ",
           "ksef_number" => ""
         }}
      end)

      assert {:ok, %Invoice{} = invoice} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{type: :expense})

      assert invoice.seller_address["street"] == "ul. Testowa 1"
      assert invoice.seller_address["city"] == "Warszawa"
      assert invoice.buyer_address["street"] == "ul. Kupna 5"
      assert invoice.buyer_address["country"] == "PL"
      assert invoice.iban == "PL61109010140000071219812874"
      assert invoice.swift_bic == "BPKOPLPW"
      assert invoice.bank_name == "PKO BP"
      assert invoice.bank_address == "ul. Bankowa 1, Warszawa"
      assert invoice.routing_number == nil
      assert invoice.account_number == nil
      assert invoice.payment_instructions == "Reference: FV/FLAT/001"
      assert invoice.ksef_number == nil
      assert invoice.purchase_order == "AU_CON_NW9BBJ4VJ"
    end

    test "treats extraction placeholder values as nil", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "Test Seller",
           "invoice_number" => "FV/PLACEHOLDER/001",
           "issue_date" => "2026-03-01",
           "net_amount" => "100.00",
           "gross_amount" => "123.00",
           "currency" => "PLN",
           "ksef_number" => "`",
           "bank_swift_bic" => "-",
           "bank_name" => "N/A",
           "bank_routing_number" => "--"
         }}
      end)

      assert {:ok, %Invoice{} = invoice} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{type: :expense})

      assert invoice.ksef_number == nil
      assert invoice.swift_bic == nil
      assert invoice.bank_name == nil
      assert invoice.routing_number == nil
    end

    test "stores created_by_id when provided in opts", %{company: company} do
      user = insert(:user)
      insert(:membership, user: user, company: company, role: :owner)

      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "Seller",
           "buyer_nip" => company.nip,
           "buyer_name" => "Buyer",
           "invoice_number" => "FV/PDF/CB",
           "issue_date" => "2026-02-20",
           "net_amount" => "1000.00",
           "gross_amount" => "1230.00"
         }}
      end)

      assert {:ok, %Invoice{} = invoice} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{
                 type: :expense,
                 filename: "created_by.pdf",
                 created_by_id: user.id
               })

      assert invoice.created_by_id == user.id
    end

    test "stores created_by_id even when extraction fails", %{company: company} do
      user = insert(:user)
      insert(:membership, user: user, company: company, role: :owner)

      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:error, {:extractor_error, 500}}
      end)

      assert {:ok, %Invoice{} = invoice} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{
                 type: :expense,
                 filename: "failed_cb.pdf",
                 created_by_id: user.id
               })

      assert invoice.created_by_id == user.id
      assert invoice.extraction_status == :failed
    end

    test "rejects expense when extracted buyer NIP doesn't match company", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "Seller",
           "buyer_nip" => "9999999999",
           "buyer_name" => "Wrong Company",
           "invoice_number" => "FV/MISMATCH/001",
           "issue_date" => "2026-02-20",
           "net_amount" => "1000.00",
           "gross_amount" => "1230.00"
         }}
      end)

      assert {:error, :buyer_nip_mismatch} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{type: :expense})
    end

    test "accepts expense when buyer NIP not extracted (fallback to company fields)", %{
      company: company
    } do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "Seller",
           "invoice_number" => "FV/NO_NIP/001",
           "issue_date" => "2026-02-20",
           "net_amount" => "1000.00",
           "gross_amount" => "1230.00"
         }}
      end)

      assert {:ok, %Invoice{} = invoice} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{type: :expense})

      assert invoice.buyer_nip == company.nip
      assert invoice.buyer_name == company.name
    end

    test "accepts expense with PL-prefixed buyer NIP matching company", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "Seller",
           "buyer_nip" => "PL#{company.nip}",
           "buyer_name" => "Buyer",
           "invoice_number" => "FV/PL/001",
           "issue_date" => "2026-02-20",
           "net_amount" => "1000.00",
           "gross_amount" => "1230.00"
         }}
      end)

      assert {:ok, %Invoice{}} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{type: :expense})
    end

    # String type variants — covers the API path where type comes as a string from params
    test "rejects expense (string type) when buyer NIP doesn't match", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "Seller",
           "buyer_nip" => "9999999999",
           "buyer_name" => "Wrong Company",
           "invoice_number" => "FV/STR/001",
           "issue_date" => "2026-02-20",
           "net_amount" => "1000.00",
           "gross_amount" => "1230.00"
         }}
      end)

      assert {:error, :buyer_nip_mismatch} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{type: "expense"})
    end

    test "accepts expense (string type) when buyer NIP not extracted", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "Seller",
           "invoice_number" => "FV/STR/002",
           "issue_date" => "2026-02-20",
           "net_amount" => "1000.00",
           "gross_amount" => "1230.00"
         }}
      end)

      assert {:ok, %Invoice{} = invoice} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{type: "expense"})

      assert invoice.buyer_nip == company.nip
    end

    test "accepts expense (string type) with PL-prefixed buyer NIP", %{company: company} do
      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "Seller",
           "buyer_nip" => "PL#{company.nip}",
           "buyer_name" => "Buyer",
           "invoice_number" => "FV/STR/003",
           "issue_date" => "2026-02-20",
           "net_amount" => "1000.00",
           "gross_amount" => "1230.00"
         }}
      end)

      assert {:ok, %Invoice{}} =
               Invoices.create_pdf_upload_invoice(company, "pdf-data", %{type: "expense"})
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

      assert {:ok, %Invoice{expense_approval_status: :approved}} =
               Invoices.approve_invoice(invoice)
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

      assert {:ok, %Invoice{expense_approval_status: :approved}} =
               Invoices.approve_invoice(invoice)
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
        |> Map.put(:xml_content, @sample_xml)

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
        |> Map.put(:xml_content, @sample_xml)

      assert {:ok, %Invoice{extraction_status: :complete}, :updated} =
               Invoices.upsert_invoice(attrs)
    end
  end

  describe "update_invoice_fields/2" do
    test "returns error for KSeF invoices", %{company: company} do
      invoice = insert(:invoice, company: company)

      assert {:error, :ksef_not_editable} =
               Invoices.update_invoice_fields(invoice, %{"net_amount" => "1000.00"})
    end

    test "rejects update when invoice source changed to ksef after struct was loaded", %{
      company: company
    } do
      ksef_number = "stale-race-#{System.unique_integer([:positive])}"

      stale_invoice =
        insert(:pdf_upload_invoice,
          company: company,
          ksef_number: ksef_number,
          extraction_status: :partial
        )

      # Simulate concurrent upsert that transitions the row to :ksef
      upsert_attrs =
        params_for(:invoice,
          ksef_number: ksef_number,
          company_id: company.id,
          source: :ksef
        )
        |> Map.put(:xml_content, @sample_xml)

      assert {:ok, %Invoice{source: :ksef}, _action} = Invoices.upsert_invoice(upsert_attrs)

      # The stale struct still has source: :pdf_upload, but the DB row is now :ksef
      assert stale_invoice.source == :pdf_upload

      assert {:error, :ksef_not_editable} =
               Invoices.update_invoice_fields(stale_invoice, %{"net_amount" => "1000.00"})
    end

    test "updates invoice fields and recalculates extraction_status to complete", %{
      company: company
    } do
      invoice =
        insert(:pdf_upload_invoice,
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
        insert(:pdf_upload_invoice,
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

    test "accepts foreign tax ID in seller_nip for non-KSeF invoices", %{company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      attrs = %{"seller_nip" => "FR61823475082"}

      assert {:ok, updated} = Invoices.update_invoice_fields(invoice, attrs)
      assert updated.seller_nip == "FR61823475082"
    end

    test "succeeds for manual invoices", %{company: company} do
      invoice = insert(:manual_invoice, company: company)
      attrs = %{"seller_nip" => "9999999999"}
      assert {:ok, updated} = Invoices.update_invoice_fields(invoice, attrs)
      assert updated.seller_nip == "9999999999"
    end

    test "rejects seller_nip exceeding max length", %{company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      attrs = %{"seller_nip" => String.duplicate("1", 51)}

      assert {:error, changeset} = Invoices.update_invoice_fields(invoice, attrs)
      assert errors_on(changeset).seller_nip
    end

    test "company-side fields in attrs do not flip extraction_status to complete", %{
      company: company
    } do
      # Expense invoice with partial extraction (missing seller fields)
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          type: :expense,
          extraction_status: :partial,
          seller_nip: nil,
          seller_name: nil,
          buyer_nip: company.nip,
          buyer_name: company.name,
          invoice_number: "FV/1",
          issue_date: ~D[2025-01-01],
          net_amount: Decimal.new("100"),
          gross_amount: Decimal.new("123")
        )

      # Submit buyer fields (company-owned for expense) — these should be ignored
      attrs = %{
        "buyer_nip" => "9999999999",
        "buyer_name" => "Injected Corp"
      }

      assert {:ok, updated} = Invoices.update_invoice_fields(invoice, attrs)
      # Status should stay :partial because seller fields are still missing
      assert updated.extraction_status == :partial
      # Company-owned buyer fields should remain unchanged
      assert updated.buyer_nip == company.nip
      assert updated.buyer_name == company.name
    end

    test "backfills billing_date when issue_date is set on invoice with nil billing dates", %{
      company: company
    } do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :partial,
          issue_date: nil,
          billing_date_from: nil,
          billing_date_to: nil
        )

      attrs = %{"issue_date" => "2026-03-15"}

      assert {:ok, updated} = Invoices.update_invoice_fields(invoice, attrs)
      assert updated.issue_date == ~D[2026-03-15]
      assert updated.billing_date_from == ~D[2026-03-01]
      assert updated.billing_date_to == ~D[2026-03-01]
    end

    test "does not overwrite existing billing_date when issue_date changes", %{
      company: company
    } do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          issue_date: ~D[2026-02-10],
          billing_date_from: ~D[2026-01-01],
          billing_date_to: ~D[2026-01-31]
        )

      attrs = %{"issue_date" => "2026-03-15"}

      assert {:ok, updated} = Invoices.update_invoice_fields(invoice, attrs)
      assert updated.issue_date == ~D[2026-03-15]
      assert updated.billing_date_from == ~D[2026-01-01]
      assert updated.billing_date_to == ~D[2026-01-31]
    end

    test "backfills billing_date from sales_date when issue_date is nil", %{company: company} do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :partial,
          issue_date: nil,
          billing_date_from: nil,
          billing_date_to: nil
        )

      attrs = %{"sales_date" => "2026-04-20"}

      assert {:ok, updated} = Invoices.update_invoice_fields(invoice, attrs)
      assert updated.billing_date_from == ~D[2026-04-01]
      assert updated.billing_date_to == ~D[2026-04-01]
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

    test "creates invoice with foreign (non-Polish) seller NIP", %{company: company} do
      pdf_binary = "%PDF-1.4 fake french invoice"

      extracted = %{
        "seller_nip" => "FR61823475082",
        "seller_name" => "LEMPIRE SAS",
        "buyer_nip" => company.nip,
        "buyer_name" => "Buyer S.A.",
        "invoice_number" => "FA-2026-001",
        "issue_date" => "2026-02-15",
        "net_amount" => "500.00",
        "gross_amount" => "600.00"
      }

      assert {:ok, invoice} =
               Invoices.create_email_invoice(company.id, pdf_binary, extracted,
                 filename: "french_invoice.pdf"
               )

      assert invoice.source == :email
      assert invoice.seller_nip == "FR61823475082"
      assert invoice.seller_name == "LEMPIRE SAS"
      assert invoice.extraction_status == :complete
    end
  end

  describe "auto-approval on creation" do
    test "auto-approves manual invoice when company setting is enabled", %{company: company} do
      company
      |> Ecto.Changeset.change(auto_approve_trusted_invoices: true)
      |> Repo.update!()

      attrs = params_for(:manual_invoice)

      assert {:ok, invoice} = Invoices.create_manual_invoice(company.id, attrs)
      assert invoice.expense_approval_status == :approved
    end

    test "leaves manual invoice as pending when company setting is disabled", %{
      company: company
    } do
      attrs = params_for(:manual_invoice)

      assert {:ok, invoice} = Invoices.create_manual_invoice(company.id, attrs)
      assert invoice.expense_approval_status == :pending
    end

    test "auto-approves email invoice when sender is a company member", %{company: company} do
      company =
        company
        |> Ecto.Changeset.change(auto_approve_trusted_invoices: true)
        |> Repo.update!()

      user = insert(:user, email: "member@appunite.com")
      insert(:membership, user: user, company: company, status: :active)

      extracted = %{
        "seller_nip" => "1111111111",
        "seller_name" => "Seller",
        "buyer_nip" => company.nip,
        "buyer_name" => "Buyer",
        "invoice_number" => "FV/2026/EAUTO",
        "issue_date" => "2026-02-25",
        "net_amount" => "1000.00",
        "gross_amount" => "1230.00"
      }

      assert {:ok, invoice} =
               Invoices.create_email_invoice(company.id, "%PDF-1.4", extracted,
                 filename: "inv.pdf",
                 sender_email: "member@appunite.com"
               )

      assert invoice.expense_approval_status == :approved
    end

    test "leaves email invoice as pending when sender is not a company member", %{
      company: company
    } do
      company
      |> Ecto.Changeset.change(auto_approve_trusted_invoices: true)
      |> Repo.update!()

      extracted = %{
        "seller_nip" => "1111111111",
        "seller_name" => "Seller",
        "buyer_nip" => company.nip,
        "buyer_name" => "Buyer",
        "invoice_number" => "FV/2026/ENOMEM",
        "issue_date" => "2026-02-25",
        "net_amount" => "1000.00",
        "gross_amount" => "1230.00"
      }

      assert {:ok, invoice} =
               Invoices.create_email_invoice(company.id, "%PDF-1.4", extracted,
                 filename: "inv.pdf",
                 sender_email: "stranger@example.com"
               )

      assert invoice.expense_approval_status == :pending
    end

    test "does not auto-approve KSeF invoices even when setting is enabled", %{company: company} do
      company
      |> Ecto.Changeset.change(auto_approve_trusted_invoices: true)
      |> Repo.update!()

      attrs =
        params_for(:invoice,
          company_id: company.id,
          type: :expense,
          ksef_number: "ksef-auto-test"
        )
        |> Map.put(:xml_content, @sample_xml)

      assert {:ok, invoice, :inserted} = Invoices.upsert_invoice(attrs)
      assert invoice.expense_approval_status == :pending
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
        |> Map.put(:xml_content, @sample_xml)

      assert {:ok, updated, :updated} = Invoices.upsert_invoice(attrs)
      assert updated.seller_name == "KSeF Seller"
      assert updated.source == :ksef
    end
  end

  describe "dismiss_extraction_warning/2" do
    test "sets extraction_status to :complete", %{company: company} do
      invoice =
        insert(:pdf_upload_invoice, company: company, extraction_status: :partial)

      assert {:ok, updated} = Invoices.dismiss_extraction_warning(invoice)
      assert updated.extraction_status == :complete
    end

    test "is a no-op when already complete", %{company: company} do
      invoice =
        insert(:pdf_upload_invoice, company: company, extraction_status: :complete)

      assert {:ok, updated} = Invoices.dismiss_extraction_warning(invoice)
      assert updated.extraction_status == :complete
    end

    test "works for failed extraction_status", %{company: company} do
      invoice =
        insert(:pdf_upload_invoice, company: company, extraction_status: :failed)

      assert {:ok, updated} = Invoices.dismiss_extraction_warning(invoice)
      assert updated.extraction_status == :complete
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

  # --- Invoice Notes ---

  describe "update_invoice_note/2" do
    test "updates the note on an invoice", %{company: company} do
      invoice = insert(:invoice, company: company)

      assert {:ok, updated} = Invoices.update_invoice_note(invoice, %{note: "Ask Jan about this"})
      assert updated.note == "Ask Jan about this"
    end

    test "clears the note when set to nil", %{company: company} do
      invoice = insert(:invoice, company: company, note: "old note")

      assert {:ok, updated} = Invoices.update_invoice_note(invoice, %{note: nil})
      assert is_nil(updated.note)
    end

    test "rejects note exceeding 5000 characters", %{company: company} do
      invoice = insert(:invoice, company: company)
      long_note = String.duplicate("a", 5001)

      assert {:error, changeset} = Invoices.update_invoice_note(invoice, %{note: long_note})
      assert errors_on(changeset).note
    end
  end

  describe "create_manual_invoice/2 company field auto-population" do
    test "auto-populates buyer_nip and buyer_name for expense", %{company: company} do
      attrs = %{
        type: :expense,
        seller_nip: "9999999999",
        seller_name: "External Seller",
        invoice_number: "FV/2026/AUTO-1",
        issue_date: ~D[2026-02-20],
        net_amount: Decimal.new("1000.00"),
        gross_amount: Decimal.new("1230.00")
      }

      assert {:ok, invoice} = Invoices.create_manual_invoice(company.id, attrs)
      assert invoice.buyer_nip == company.nip
      assert invoice.buyer_name == company.name
      assert invoice.seller_nip == "9999999999"
    end

    test "auto-populates seller_nip and seller_name for income", %{company: company} do
      attrs = %{
        type: :income,
        buyer_nip: "9999999999",
        buyer_name: "External Buyer",
        invoice_number: "FV/2026/AUTO-2",
        issue_date: ~D[2026-02-20],
        net_amount: Decimal.new("1000.00"),
        gross_amount: Decimal.new("1230.00")
      }

      assert {:ok, invoice} = Invoices.create_manual_invoice(company.id, attrs)
      assert invoice.seller_nip == company.nip
      assert invoice.seller_name == company.name
      assert invoice.buyer_nip == "9999999999"
    end
  end

  describe "data_editable?/1" do
    test "returns false for KSeF invoices" do
      assert Invoice.data_editable?(%Invoice{source: :ksef}) == false
    end

    test "returns true for manual invoices" do
      assert Invoice.data_editable?(%Invoice{source: :manual}) == true
    end

    test "returns true for pdf_upload invoices" do
      assert Invoice.data_editable?(%Invoice{source: :pdf_upload}) == true
    end

    test "returns true for email invoices" do
      assert Invoice.data_editable?(%Invoice{source: :email}) == true
    end
  end

  describe "edit_changeset/2 KSeF guard" do
    test "returns invalid changeset with error for KSeF invoices" do
      invoice = %Invoice{source: :ksef, type: :expense}
      changeset = Invoice.edit_changeset(invoice, %{seller_name: "New Name"})
      refute changeset.valid?
      assert {"ksef invoices cannot be edited", _} = changeset.errors[:source]
    end
  end

  describe "edit_changeset/2 company field protection" do
    test "ignores buyer fields for expense invoices", %{company: company} do
      invoice = insert(:pdf_upload_invoice, company: company, type: :expense)

      changeset =
        Invoice.edit_changeset(invoice, %{
          buyer_nip: "HACKED",
          buyer_name: "Hacker Inc",
          seller_nip: "5555555555",
          seller_name: "New Seller"
        })

      # buyer fields should NOT be in changes
      refute Map.has_key?(changeset.changes, :buyer_nip)
      refute Map.has_key?(changeset.changes, :buyer_name)
      # seller fields should be in changes
      assert changeset.changes[:seller_nip] == "5555555555"
      assert changeset.changes[:seller_name] == "New Seller"
    end

    test "ignores seller fields for income invoices", %{company: company} do
      invoice = insert(:pdf_upload_invoice, company: company, type: :income)

      changeset =
        Invoice.edit_changeset(invoice, %{
          seller_nip: "HACKED",
          seller_name: "Hacker Inc",
          buyer_nip: "5555555555",
          buyer_name: "New Buyer"
        })

      # seller fields should NOT be in changes
      refute Map.has_key?(changeset.changes, :seller_nip)
      refute Map.has_key?(changeset.changes, :seller_name)
      # buyer fields should be in changes
      assert changeset.changes[:buyer_nip] == "5555555555"
      assert changeset.changes[:buyer_name] == "New Buyer"
    end
  end

  describe "purchase_order" do
    test "upsert stores purchase_order from parsed XML", %{company: company} do
      xml = File.read!("test/support/fixtures/sample_income_with_po.xml")

      attrs =
        params_for(:invoice, ksef_number: "po-upsert-1", company_id: company.id)
        |> Map.put(:xml_content, xml)
        |> Map.put(:purchase_order, "PO-2025-001")

      assert {:ok, %Invoice{} = invoice, :inserted} = Invoices.upsert_invoice(attrs)
      assert invoice.purchase_order == "PO-2025-001"
    end

    test "upsert updates purchase_order on re-sync", %{company: company} do
      insert(:invoice,
        ksef_number: "po-resync",
        company: company,
        purchase_order: "OLD-PO",
        inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
      )

      attrs =
        params_for(:invoice, ksef_number: "po-resync", company_id: company.id)
        |> Map.put(:xml_content, @sample_xml)
        |> Map.put(:purchase_order, "NEW-PO")

      {:ok, updated, :updated} = Invoices.upsert_invoice(attrs)
      assert updated.purchase_order == "NEW-PO"
    end

    test "update_invoice_fields updates purchase_order", %{company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      assert {:ok, updated} =
               Invoices.update_invoice_fields(invoice, %{"purchase_order" => "PO-EDITED"})

      assert updated.purchase_order == "PO-EDITED"
    end

    test "search matches purchase_order", %{company: company} do
      insert(:invoice, purchase_order: "PO-FINDME-123", company: company)
      insert(:invoice, purchase_order: nil, company: company)

      results = Invoices.list_invoices(company.id, %{query: "FINDME"})
      assert length(results) == 1
      assert hd(results).purchase_order == "PO-FINDME-123"
    end

    test "edit_changeset validates purchase_order max length" do
      invoice = %Invoice{type: :expense, source: :pdf_upload}

      changeset =
        Invoice.edit_changeset(invoice, %{purchase_order: String.duplicate("x", 257)})

      assert {"should be at most %{count} character(s)", _} = changeset.errors[:purchase_order]
    end

    test "edit_changeset accepts valid purchase_order" do
      invoice = %Invoice{type: :expense, source: :pdf_upload}

      changeset = Invoice.edit_changeset(invoice, %{purchase_order: "PO-2025-001"})
      assert changeset.valid?
      assert changeset.changes[:purchase_order] == "PO-2025-001"
    end
  end

  describe "extraction fields (sales_date, due_date, iban, addresses)" do
    test "upsert stores provided sales_date, iban, and addresses when passed in attrs", %{
      company: company
    } do
      xml = File.read!("test/support/fixtures/sample_income_with_bank_details.xml")

      attrs =
        params_for(:invoice, ksef_number: "iban-upsert-1", company_id: company.id)
        |> Map.put(:xml_content, xml)
        |> Map.put(:sales_date, ~D[2025-01-14])
        |> Map.put(:iban, "PL61109010140000071219812874")
        |> Map.put(:seller_address, %{
          street: "ul. Testowa 1",
          city: "00-001 Warszawa",
          postal_code: nil,
          country: "PL"
        })
        |> Map.put(:buyer_address, %{
          street: "ul. Kupna 5",
          city: "00-002 Kraków",
          postal_code: nil,
          country: "PL"
        })

      assert {:ok, %Invoice{} = invoice, :inserted} = Invoices.upsert_invoice(attrs)
      assert invoice.sales_date == ~D[2025-01-14]
      assert invoice.iban == "PL61109010140000071219812874"
      assert invoice.seller_address["street"] == "ul. Testowa 1"
      assert invoice.buyer_address["street"] == "ul. Kupna 5"
    end

    test "update_invoice_fields updates sales_date, due_date, iban", %{company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      attrs = %{
        "sales_date" => "2025-06-01",
        "due_date" => "2025-07-01",
        "iban" => "PL61109010140000071219812874"
      }

      assert {:ok, updated} = Invoices.update_invoice_fields(invoice, attrs)
      assert updated.sales_date == ~D[2025-06-01]
      assert updated.due_date == ~D[2025-07-01]
      assert updated.iban == "PL61109010140000071219812874"
    end

    test "search matches iban", %{company: company} do
      insert(:invoice, iban: "PL61109010140000071219812874", company: company)
      insert(:invoice, iban: nil, company: company)

      results = Invoices.list_invoices(company.id, %{query: "PL611090"})
      assert length(results) == 1
      assert hd(results).iban == "PL61109010140000071219812874"
    end

    test "search matches ksef_number", %{company: company} do
      insert(:invoice, ksef_number: "KSEF-2025-UNIQUE-999", company: company)
      insert(:invoice, ksef_number: "KSEF-2025-OTHER-001", company: company)

      results = Invoices.list_invoices(company.id, %{query: "UNIQUE-999"})
      assert length(results) == 1
      assert hd(results).ksef_number == "KSEF-2025-UNIQUE-999"
    end

    test "search matches gross_amount as substring", %{company: company} do
      insert(:invoice, gross_amount: Decimal.new("1234.56"), company: company)
      insert(:invoice, gross_amount: Decimal.new("9999.00"), company: company)

      results = Invoices.list_invoices(company.id, %{query: "1234"})
      assert length(results) == 1
      assert Decimal.equal?(hd(results).gross_amount, Decimal.new("1234.56"))
    end

    test "search matches net_amount as substring", %{company: company} do
      insert(:invoice, net_amount: Decimal.new("5678.90"), company: company)
      insert(:invoice, net_amount: Decimal.new("1111.00"), company: company)

      results = Invoices.list_invoices(company.id, %{query: "5678"})
      assert length(results) == 1
      assert Decimal.equal?(hd(results).net_amount, Decimal.new("5678.90"))
    end

    test "edit_changeset validates iban max length" do
      invoice = %Invoice{type: :expense, source: :pdf_upload}

      changeset = Invoice.edit_changeset(invoice, %{iban: String.duplicate("X", 35)})

      assert {"should be at most %{count} character(s)", _} = changeset.errors[:iban]
    end

    test "edit_changeset validates iban min length" do
      invoice = %Invoice{type: :expense, source: :pdf_upload}

      changeset = Invoice.edit_changeset(invoice, %{iban: "PL6110901014"})

      assert {"should be at least %{count} character(s)", _} = changeset.errors[:iban]
    end

    test "edit_changeset accepts valid iban" do
      invoice = %Invoice{type: :expense, source: :pdf_upload}

      changeset = Invoice.edit_changeset(invoice, %{iban: "PL61109010140000071219812874"})
      assert changeset.valid?
      assert changeset.changes[:iban] == "PL61109010140000071219812874"
    end
  end

  describe "Invoice.format_address/1" do
    test "formats atom-keyed address map" do
      addr = %{street: "ul. Testowa 1", city: "Warszawa", postal_code: "00-001", country: "PL"}
      assert Invoice.format_address(addr) == "ul. Testowa 1, Warszawa, 00-001, PL"
    end

    test "formats string-keyed address map (JSONB round-trip)" do
      addr = %{"street" => "ul. Testowa 1", "city" => "Warszawa", "country" => "PL"}
      assert Invoice.format_address(addr) == "ul. Testowa 1, Warszawa, PL"
    end

    test "skips nil and empty values" do
      addr = %{street: "ul. Testowa 1", city: nil, postal_code: "", country: "PL"}
      assert Invoice.format_address(addr) == "ul. Testowa 1, PL"
    end

    test "skips whitespace-only values and trims others" do
      addr = %{street: " ul. Testowa 1 ", city: "   ", postal_code: nil, country: "PL"}
      assert Invoice.format_address(addr) == "ul. Testowa 1, PL"
    end

    test "returns empty string for nil" do
      assert Invoice.format_address(nil) == ""
    end

    test "returns empty string when all values nil" do
      addr = %{street: nil, city: nil, postal_code: nil, country: nil}
      assert Invoice.format_address(addr) == ""
    end
  end

  describe "edit_changeset/2 address normalization" do
    test "accepts valid address map" do
      invoice = %Invoice{type: :expense, source: :pdf_upload}

      changeset =
        Invoice.edit_changeset(invoice, %{
          seller_address: %{"street" => "ul. Nowa 5", "city" => "Kraków"}
        })

      assert changeset.valid?
      assert changeset.changes[:seller_address] == %{"street" => "ul. Nowa 5", "city" => "Kraków"}
    end

    test "normalizes all-blank address to nil" do
      invoice = %Invoice{type: :expense, source: :pdf_upload}

      changeset =
        Invoice.edit_changeset(invoice, %{
          seller_address: %{"street" => "", "city" => "", "postal_code" => "", "country" => ""}
        })

      assert changeset.valid?
      assert changeset.changes[:seller_address] == nil
    end

    test "keeps partial address (some sub-fields blank)" do
      invoice = %Invoice{type: :expense, source: :pdf_upload}

      changeset =
        Invoice.edit_changeset(invoice, %{
          buyer_address: %{
            "street" => "ul. Nowa 5",
            "city" => "",
            "postal_code" => "",
            "country" => ""
          }
        })

      assert changeset.valid?

      assert changeset.changes[:buyer_address] == %{
               "street" => "ul. Nowa 5",
               "city" => "",
               "postal_code" => "",
               "country" => ""
             }
    end

    test "normalizes nil-only address map to nil" do
      invoice = %Invoice{type: :expense, source: :pdf_upload}

      changeset =
        Invoice.edit_changeset(invoice, %{
          seller_address: %{"street" => nil, "city" => nil}
        })

      assert changeset.valid?
      assert changeset.changes[:seller_address] == nil
    end

    test "normalizes whitespace-only address to nil" do
      invoice = %Invoice{type: :expense, source: :pdf_upload}

      changeset =
        Invoice.edit_changeset(invoice, %{
          seller_address: %{
            "street" => "   ",
            "city" => " ",
            "postal_code" => "",
            "country" => nil
          }
        })

      assert changeset.valid?
      assert changeset.changes[:seller_address] == nil
    end
  end

  describe "billing_date_range" do
    test "auto-computes billing_date_from/to from sales_date on create", %{company: company} do
      attrs =
        params_for(:invoice,
          company_id: company.id,
          sales_date: ~D[2026-02-15],
          issue_date: ~D[2026-02-10]
        )
        |> Map.delete(:billing_date_from)
        |> Map.delete(:billing_date_to)
        |> Map.put(:xml_content, @sample_xml)

      assert {:ok, invoice} = Invoices.create_invoice(attrs)
      assert invoice.billing_date_from == ~D[2026-02-01]
      assert invoice.billing_date_to == ~D[2026-02-01]
    end

    test "auto-computes billing_date_from/to from issue_date when no sales_date", %{
      company: company
    } do
      attrs =
        params_for(:invoice,
          company_id: company.id,
          sales_date: nil,
          issue_date: ~D[2026-03-20]
        )
        |> Map.delete(:billing_date_from)
        |> Map.delete(:billing_date_to)
        |> Map.put(:xml_content, @sample_xml)

      assert {:ok, invoice} = Invoices.create_invoice(attrs)
      assert invoice.billing_date_from == ~D[2026-03-01]
      assert invoice.billing_date_to == ~D[2026-03-01]
    end

    test "explicit billing_date_from/to overrides auto-computation", %{company: company} do
      attrs =
        params_for(:pdf_upload_invoice,
          company_id: company.id,
          sales_date: ~D[2026-02-15],
          billing_date_from: ~D[2026-04-01],
          billing_date_to: ~D[2026-06-01]
        )
        |> Map.put(:pdf_content, "%PDF-1.4 test")

      assert {:ok, invoice} = Invoices.create_invoice(attrs)
      assert invoice.billing_date_from == ~D[2026-04-01]
      assert invoice.billing_date_to == ~D[2026-06-01]
    end

    test "explicit billing_date_from nil preserves nil despite dates being present", %{
      company: company
    } do
      attrs =
        params_for(:invoice,
          company_id: company.id,
          sales_date: ~D[2026-02-15],
          issue_date: ~D[2026-02-10]
        )
        |> Map.put(:billing_date_from, nil)
        |> Map.put(:billing_date_to, nil)
        |> Map.put(:xml_content, @sample_xml)

      assert {:ok, invoice} = Invoices.create_invoice(attrs)
      assert is_nil(invoice.billing_date_from)
      assert is_nil(invoice.billing_date_to)
    end

    test "validates billing_date_to >= billing_date_from", %{company: company} do
      attrs =
        params_for(:invoice,
          company_id: company.id,
          billing_date_from: ~D[2026-06-01],
          billing_date_to: ~D[2026-04-01]
        )
        |> Map.put(:xml_content, @sample_xml)

      assert {:error, changeset} = Invoices.create_invoice(attrs)
      assert "must be on or after billing_date_from" in errors_on(changeset).billing_date_to
    end

    test "filters by billing_date_from and billing_date_to with overlap semantics", %{
      company: company
    } do
      insert(:invoice,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-01-01],
        issue_date: ~D[2026-01-15]
      )

      insert(:invoice,
        company: company,
        billing_date_from: ~D[2026-02-01],
        billing_date_to: ~D[2026-02-01],
        issue_date: ~D[2026-02-15]
      )

      insert(:invoice,
        company: company,
        billing_date_from: ~D[2026-03-01],
        billing_date_to: ~D[2026-03-01],
        issue_date: ~D[2026-03-15]
      )

      result =
        Invoices.list_invoices(company.id, %{
          billing_date_from: ~D[2026-02-01],
          billing_date_to: ~D[2026-02-28]
        })

      assert length(result) == 1
      assert hd(result).billing_date_from == ~D[2026-02-01]
    end

    test "multi-month invoice overlaps with filter range", %{company: company} do
      insert(:invoice,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-03-01],
        issue_date: ~D[2026-01-15]
      )

      result =
        Invoices.list_invoices(company.id, %{billing_date_from: ~D[2026-02-01]})

      assert length(result) == 1
    end

    test "filters by billing_date_from only", %{company: company} do
      insert(:invoice,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-01-01],
        issue_date: ~D[2026-01-15]
      )

      insert(:invoice,
        company: company,
        billing_date_from: ~D[2026-03-01],
        billing_date_to: ~D[2026-03-01],
        issue_date: ~D[2026-03-15]
      )

      result =
        Invoices.list_invoices(company.id, %{billing_date_from: ~D[2026-02-01]})

      assert length(result) == 1
      assert hd(result).billing_date_from == ~D[2026-03-01]
    end

    test "filters by billing_date_to only", %{company: company} do
      insert(:invoice,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-01-01],
        issue_date: ~D[2026-01-15]
      )

      insert(:invoice,
        company: company,
        billing_date_from: ~D[2026-03-01],
        billing_date_to: ~D[2026-03-01],
        issue_date: ~D[2026-03-15]
      )

      result =
        Invoices.list_invoices(company.id, %{billing_date_to: ~D[2026-01-31]})

      assert length(result) == 1
      assert hd(result).billing_date_from == ~D[2026-01-01]
    end

    test "billing_date_from/to are nil when both sales_date and issue_date are nil", %{
      company: company
    } do
      attrs =
        params_for(:pdf_upload_invoice,
          company_id: company.id,
          sales_date: nil,
          issue_date: nil
        )
        |> Map.delete(:billing_date_from)
        |> Map.delete(:billing_date_to)
        |> Map.put(:pdf_content, "%PDF-1.4 test")

      assert {:ok, invoice} = Invoices.create_invoice(attrs)
      assert is_nil(invoice.billing_date_from)
      assert is_nil(invoice.billing_date_to)
    end

    test "auto-computes billing_date_from/to on upsert", %{company: company} do
      attrs = %{
        company_id: company.id,
        type: :income,
        source: :ksef,
        ksef_number: "upsert-bd-test-001",
        seller_nip: "1234567890",
        seller_name: "Seller Sp. z o.o.",
        buyer_nip: "0987654321",
        buyer_name: "Buyer S.A.",
        invoice_number: "FV/BD/001",
        issue_date: ~D[2026-05-20],
        sales_date: ~D[2026-05-15],
        net_amount: Decimal.new("1000.00"),
        gross_amount: Decimal.new("1230.00"),
        xml_content: @sample_xml
      }

      assert {:ok, invoice, :inserted} = Invoices.upsert_invoice(attrs)
      assert invoice.billing_date_from == ~D[2026-05-01]
      assert invoice.billing_date_to == ~D[2026-05-01]
    end

    test "update_billing_date works on KSeF income invoices (single month)", %{company: company} do
      invoice =
        insert(:invoice,
          company: company,
          source: :ksef,
          billing_date_from: ~D[2026-01-01],
          billing_date_to: ~D[2026-01-01]
        )

      assert {:ok, updated} =
               Invoices.update_billing_date(invoice, %{
                 billing_date_from: ~D[2026-06-01],
                 billing_date_to: ~D[2026-06-01]
               })

      assert updated.billing_date_from == ~D[2026-06-01]
      assert updated.billing_date_to == ~D[2026-06-01]
    end

    test "update_billing_date rejects range for income invoices", %{company: company} do
      invoice =
        insert(:invoice,
          company: company,
          billing_date_from: ~D[2026-01-01],
          billing_date_to: ~D[2026-01-01]
        )

      assert {:error, changeset} =
               Invoices.update_billing_date(invoice, %{
                 billing_date_from: ~D[2026-06-01],
                 billing_date_to: ~D[2026-08-01]
               })

      assert "must equal billing_date_from for income invoices" in errors_on(changeset).billing_date_to
    end

    test "update_billing_date allows range for expense invoices", %{company: company} do
      invoice =
        insert(:manual_invoice,
          company: company,
          billing_date_from: ~D[2026-01-01],
          billing_date_to: ~D[2026-01-01]
        )

      assert {:ok, updated} =
               Invoices.update_billing_date(invoice, %{
                 billing_date_from: ~D[2026-06-01],
                 billing_date_to: ~D[2026-08-01]
               })

      assert updated.billing_date_from == ~D[2026-06-01]
      assert updated.billing_date_to == ~D[2026-08-01]
    end

    test "update_billing_date can clear billing dates", %{company: company} do
      invoice =
        insert(:invoice,
          company: company,
          billing_date_from: ~D[2026-01-01],
          billing_date_to: ~D[2026-01-01]
        )

      assert {:ok, updated} =
               Invoices.update_billing_date(invoice, %{
                 billing_date_from: nil,
                 billing_date_to: nil
               })

      assert is_nil(updated.billing_date_from)
      assert is_nil(updated.billing_date_to)
    end

    test "create income invoice with range billing dates is rejected", %{company: company} do
      attrs =
        params_for(:invoice,
          company_id: company.id,
          billing_date_from: ~D[2026-04-01],
          billing_date_to: ~D[2026-06-01]
        )
        |> Map.put(:xml_content, @sample_xml)

      assert {:error, changeset} = Invoices.create_invoice(attrs)
      assert "must equal billing_date_from for income invoices" in errors_on(changeset).billing_date_to
    end

    test "create expense invoice with range billing dates is accepted", %{company: company} do
      attrs =
        params_for(:pdf_upload_invoice,
          company_id: company.id,
          billing_date_from: ~D[2026-04-01],
          billing_date_to: ~D[2026-06-01]
        )
        |> Map.put(:pdf_content, "%PDF-1.4 test")

      assert {:ok, invoice} = Invoices.create_invoice(attrs)
      assert invoice.billing_date_from == ~D[2026-04-01]
      assert invoice.billing_date_to == ~D[2026-06-01]
    end

    test "multi-month allocation distributes evenly with rounding", %{company: company} do
      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-03-01],
        net_amount: Decimal.new("100.00")
      )

      result = Invoices.expense_monthly_totals(company.id)
      assert length(result) == 3

      amounts = Enum.map(result, & &1.net_total)
      total = Enum.reduce(amounts, Decimal.new(0), &Decimal.add/2)
      assert Decimal.equal?(total, Decimal.new("100.00"))

      # First two months get 33.33, last gets 33.34
      assert Decimal.equal?(Enum.at(amounts, 0), Decimal.new("33.33"))
      assert Decimal.equal?(Enum.at(amounts, 1), Decimal.new("33.33"))
      assert Decimal.equal?(Enum.at(amounts, 2), Decimal.new("33.34"))
    end
  end

  describe "access control" do
    setup %{company: company} do
      reviewer = insert(:user)
      insert(:membership, user: reviewer, company: company, role: :reviewer)

      other_reviewer = insert(:user)
      insert(:membership, user: other_reviewer, company: company, role: :reviewer)

      admin = insert(:user)
      insert(:membership, user: admin, company: company, role: :admin)

      owner = insert(:user)
      insert(:membership, user: owner, company: company, role: :owner)

      accountant = insert(:user)
      insert(:membership, user: accountant, company: company, role: :accountant)

      %{
        reviewer: reviewer,
        other_reviewer: other_reviewer,
        admin: admin,
        owner: owner,
        accountant: accountant
      }
    end

    test "grant_access creates a grant record", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense)
      user = insert(:user)
      insert(:membership, user: user, company: company, role: :reviewer)
      granter = insert(:user)

      assert {:ok, grant} = Invoices.grant_access(invoice.id, user.id, granter.id)
      assert grant.invoice_id == invoice.id
    end

    test "grant_access is idempotent", %{company: company, reviewer: reviewer} do
      invoice = insert(:invoice, company: company, type: :expense)

      assert {:ok, _} = Invoices.grant_access(invoice.id, reviewer.id)
      assert {:ok, _} = Invoices.grant_access(invoice.id, reviewer.id)

      grants = Invoices.list_access_grants(invoice.id)
      assert length(grants) == 1
    end

    test "grant_access rejects non-member user", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense)
      outsider = insert(:user)

      assert {:error, changeset} = Invoices.grant_access(invoice.id, outsider.id)
      assert changeset.errors[:user_id]
    end

    test "grant_access rejects user with full visibility role", %{company: company, admin: admin} do
      invoice = insert(:invoice, company: company, type: :expense)

      assert {:error, changeset} = Invoices.grant_access(invoice.id, admin.id)
      assert {msg, _} = changeset.errors[:user_id]
      assert msg =~ "full access"
    end

    test "revoke_access removes a grant", %{company: company, reviewer: reviewer} do
      invoice = insert(:invoice, company: company, type: :expense)

      {:ok, _} = Invoices.grant_access(invoice.id, reviewer.id)
      assert {:ok, _} = Invoices.revoke_access(invoice.id, reviewer.id)

      assert Invoices.list_access_grants(invoice.id) == []
    end

    test "revoke_access returns error when no grant exists", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense)
      user = insert(:user)

      assert {:error, :not_found} = Invoices.revoke_access(invoice.id, user.id)
    end

    test "list_access_grants returns grants with preloaded user", %{
      company: company,
      reviewer: reviewer
    } do
      invoice = insert(:invoice, company: company, type: :expense)

      {:ok, _} = Invoices.grant_access(invoice.id, reviewer.id)
      grants = Invoices.list_access_grants(invoice.id)

      assert [grant] = grants
      assert grant.user.id == reviewer.id
    end

    test "set_access_restricted toggles the flag", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense)

      assert {:ok, updated} = Invoices.set_access_restricted(invoice, true)
      assert updated.access_restricted == true

      assert {:ok, updated} = Invoices.set_access_restricted(updated, false)
      assert updated.access_restricted == false
    end

    test "reviewer sees all invoices when access_restricted is false", %{
      company: company,
      reviewer: reviewer
    } do
      insert(:invoice, company: company, type: :expense, access_restricted: false)
      insert(:invoice, company: company, type: :expense, access_restricted: false)

      result =
        Invoices.list_invoices(company.id, %{}, role: :reviewer, user_id: reviewer.id)

      assert length(result) == 2
    end

    test "reviewer with grant sees restricted invoice", %{
      company: company,
      reviewer: reviewer
    } do
      invoice =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      Invoices.grant_access(invoice.id, reviewer.id)

      result =
        Invoices.list_invoices(company.id, %{}, role: :reviewer, user_id: reviewer.id)

      assert length(result) == 1
    end

    test "reviewer without grant does NOT see restricted invoice", %{
      company: company,
      reviewer: reviewer
    } do
      insert(:invoice, company: company, type: :expense, access_restricted: true)

      result =
        Invoices.list_invoices(company.id, %{}, role: :reviewer, user_id: reviewer.id)

      assert result == []
    end

    test "reviewer sees mix of public and restricted-but-granted invoices", %{
      company: company,
      reviewer: reviewer
    } do
      public = insert(:invoice, company: company, type: :expense, access_restricted: false)

      restricted_granted =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      _restricted_no_grant =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      Invoices.grant_access(restricted_granted.id, reviewer.id)

      result =
        Invoices.list_invoices(company.id, %{}, role: :reviewer, user_id: reviewer.id)

      ids = Enum.map(result, & &1.id) |> MapSet.new()
      assert MapSet.member?(ids, public.id)
      assert MapSet.member?(ids, restricted_granted.id)
      assert length(result) == 2
    end

    test "restricted invoice with no grants is invisible to all reviewers", %{
      company: company,
      reviewer: reviewer,
      other_reviewer: other_reviewer
    } do
      insert(:invoice, company: company, type: :expense, access_restricted: true)

      assert Invoices.list_invoices(company.id, %{},
               role: :reviewer,
               user_id: reviewer.id
             ) == []

      assert Invoices.list_invoices(company.id, %{},
               role: :reviewer,
               user_id: other_reviewer.id
             ) == []
    end

    test "owner sees all invoices regardless of access_restricted", %{
      company: company,
      owner: owner
    } do
      insert(:invoice, company: company, type: :expense, access_restricted: true)
      insert(:invoice, company: company, type: :expense, access_restricted: false)
      insert(:invoice, company: company, type: :income, access_restricted: true)

      result = Invoices.list_invoices(company.id, %{}, role: :owner, user_id: owner.id)
      assert length(result) == 3
    end

    test "admin sees all invoices regardless of access_restricted", %{
      company: company,
      admin: admin
    } do
      insert(:invoice, company: company, type: :expense, access_restricted: true)
      insert(:invoice, company: company, type: :income, access_restricted: true)

      result = Invoices.list_invoices(company.id, %{}, role: :admin, user_id: admin.id)
      assert length(result) == 2
    end

    test "accountant sees all invoices regardless of access_restricted", %{
      company: company,
      accountant: accountant
    } do
      insert(:invoice, company: company, type: :expense, access_restricted: true)
      insert(:invoice, company: company, type: :income, access_restricted: true)

      result =
        Invoices.list_invoices(company.id, %{}, role: :accountant, user_id: accountant.id)

      assert length(result) == 2
    end

    test "get_invoice returns nil for restricted invoice when reviewer lacks grant", %{
      company: company,
      reviewer: reviewer
    } do
      invoice =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      assert Invoices.get_invoice(company.id, invoice.id,
               role: :reviewer,
               user_id: reviewer.id
             ) == nil
    end

    test "get_invoice returns invoice for restricted invoice when reviewer has grant", %{
      company: company,
      reviewer: reviewer
    } do
      invoice =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      Invoices.grant_access(invoice.id, reviewer.id)

      assert %Invoice{} =
               Invoices.get_invoice(company.id, invoice.id,
                 role: :reviewer,
                 user_id: reviewer.id
               )
    end

    test "count_invoices matches filtered list for reviewer", %{
      company: company,
      reviewer: reviewer
    } do
      insert(:invoice, company: company, type: :expense, access_restricted: false)

      restricted =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      Invoices.grant_access(restricted.id, reviewer.id)

      opts = [role: :reviewer, user_id: reviewer.id]

      list = Invoices.list_invoices(company.id, %{}, opts)
      count = Invoices.count_invoices(company.id, %{}, opts)

      assert length(list) == count
      assert count == 2
    end

    test "list_invoices_paginated total_count and entries respect access filtering", %{
      company: company,
      reviewer: reviewer
    } do
      insert(:invoice, company: company, type: :expense, access_restricted: false)
      insert(:invoice, company: company, type: :expense, access_restricted: true)

      restricted_granted =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      Invoices.grant_access(restricted_granted.id, reviewer.id)

      result =
        Invoices.list_invoices_paginated(company.id, %{},
          role: :reviewer,
          user_id: reviewer.id
        )

      assert result.total_count == 2
      assert length(result.entries) == 2

      ids = MapSet.new(result.entries, & &1.id)
      assert MapSet.member?(ids, restricted_granted.id)
    end

    test "get_invoice_with_details returns nil for restricted invoice when reviewer lacks grant",
         %{company: company, reviewer: reviewer} do
      invoice =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      assert Invoices.get_invoice_with_details(company.id, invoice.id,
               role: :reviewer,
               user_id: reviewer.id
             ) == nil
    end

    test "get_invoice_with_details returns invoice when reviewer has grant", %{
      company: company,
      reviewer: reviewer
    } do
      invoice =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      Invoices.grant_access(invoice.id, reviewer.id)

      assert %Invoice{} =
               Invoices.get_invoice_with_details(company.id, invoice.id,
                 role: :reviewer,
                 user_id: reviewer.id
               )
    end

    test "income invoices are auto-restricted so reviewer cannot see them by default", %{
      company: company,
      reviewer: reviewer
    } do
      # Income invoices get access_restricted: true automatically
      attrs =
        params_for(:invoice, company_id: company.id, type: :income)
        |> Map.put(:xml_content, File.read!("test/support/fixtures/sample_income.xml"))

      {:ok, income} = Invoices.create_invoice(attrs)
      assert income.access_restricted == true

      insert(:invoice, company: company, type: :expense, access_restricted: false)

      result =
        Invoices.list_invoices(company.id, %{}, role: :reviewer, user_id: reviewer.id)

      assert length(result) == 1
      assert hd(result).type == :expense
    end

    test "expense invoices with purchase_order are auto-restricted", %{
      company: company,
      reviewer: reviewer
    } do
      attrs =
        params_for(:invoice,
          company_id: company.id,
          type: :expense,
          purchase_order: "PO-2026-001"
        )
        |> Map.put(:xml_content, File.read!("test/support/fixtures/sample_expense.xml"))

      {:ok, invoice} = Invoices.create_invoice(attrs)
      assert invoice.access_restricted == true

      insert(:invoice, company: company, type: :expense, access_restricted: false)

      result =
        Invoices.list_invoices(company.id, %{}, role: :reviewer, user_id: reviewer.id)

      assert length(result) == 1
      refute hd(result).id == invoice.id
    end

    test "upserted expense invoice with purchase_order is auto-restricted", %{
      company: company,
      reviewer: reviewer
    } do
      attrs =
        params_for(:invoice,
          company_id: company.id,
          type: :expense,
          ksef_number: "upsert-po-restrict",
          purchase_order: "PO-2026-002"
        )
        |> Map.put(:xml_content, File.read!("test/support/fixtures/sample_expense.xml"))

      assert {:ok, invoice, :inserted} = Invoices.upsert_invoice(attrs)
      assert invoice.access_restricted == true

      result =
        Invoices.list_invoices(company.id, %{}, role: :reviewer, user_id: reviewer.id)

      refute Enum.any?(result, &(&1.id == invoice.id))
    end

    test "expense invoices without purchase_order are not auto-restricted", %{company: company} do
      attrs =
        params_for(:invoice, company_id: company.id, type: :expense, purchase_order: nil)
        |> Map.put(:xml_content, File.read!("test/support/fixtures/sample_expense.xml"))

      {:ok, invoice} = Invoices.create_invoice(attrs)
      assert invoice.access_restricted == false
    end

    test "expense invoice with purchase_order can be unrestricted by admin", %{company: company} do
      invoice =
        insert(:invoice,
          company: company,
          type: :expense,
          purchase_order: "PO-123",
          access_restricted: true
        )

      assert {:ok, unrestricted} = Invoices.set_access_restricted(invoice, false)
      assert unrestricted.access_restricted == false
    end

    test "income invoice cannot be unrestricted", %{company: company} do
      invoice =
        insert(:invoice, company: company, type: :income, access_restricted: true)

      assert {:error, :income_always_restricted} =
               Invoices.set_access_restricted(invoice, false)

      # Verify it's still restricted
      reloaded = KsefHub.Repo.reload!(invoice)
      assert reloaded.access_restricted == true
    end

    test "expense invoice can be toggled freely", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense)

      assert {:ok, restricted} = Invoices.set_access_restricted(invoice, true)
      assert restricted.access_restricted == true

      assert {:ok, unrestricted} = Invoices.set_access_restricted(restricted, false)
      assert unrestricted.access_restricted == false
    end

    test "grant_access to non-member returns error", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense, access_restricted: true)
      non_member = insert(:user)

      assert {:error, changeset} = Invoices.grant_access(invoice.id, non_member.id)
      assert changeset.errors[:user_id]
    end

    test "grant_access to admin returns error (already has full access)", %{
      company: company,
      admin: admin
    } do
      invoice =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      assert {:error, changeset} = Invoices.grant_access(invoice.id, admin.id)
      assert changeset.errors[:user_id]
    end

    test "upsert_invoice auto-restricts income invoices", %{company: company} do
      attrs = %{
        company_id: company.id,
        type: :income,
        source: :ksef,
        ksef_number: "auto-restrict-test-001",
        seller_nip: "1234567890",
        seller_name: "Seller",
        buyer_nip: "0987654321",
        buyer_name: "Buyer",
        invoice_number: "FV/AR/001",
        issue_date: ~D[2026-03-01],
        net_amount: Decimal.new("100.00"),
        gross_amount: Decimal.new("123.00"),
        xml_content: File.read!("test/support/fixtures/sample_income.xml")
      }

      assert {:ok, invoice, :inserted} = Invoices.upsert_invoice(attrs)
      assert invoice.access_restricted == true
    end

    test "grants are cleaned up when invoice is deleted", %{company: company, reviewer: reviewer} do
      invoice = insert(:invoice, company: company, type: :expense)

      {:ok, _} = Invoices.grant_access(invoice.id, reviewer.id)
      assert length(Invoices.list_access_grants(invoice.id)) == 1

      KsefHub.Repo.delete!(invoice)
      assert Invoices.list_access_grants(invoice.id) == []
    end
  end

  describe "correction invoices" do
    @correction_xml File.read!("test/support/fixtures/sample_correction.xml")

    test "upsert_invoice stores correction fields", %{company: company} do
      attrs =
        params_for(:correction_invoice,
          ksef_number: "1234567890-20260415-CORR001-01",
          company_id: company.id
        )
        |> Map.put(:xml_content, @correction_xml)

      assert {:ok, invoice, :inserted} = Invoices.upsert_invoice(attrs)
      assert invoice.invoice_kind == :correction
      assert invoice.corrected_invoice_number == "FV/2026/001"
      assert invoice.corrected_invoice_ksef_number == "7831812112-20260407-5B69FA00002B-9D"
      assert invoice.correction_reason == "Błąd rachunkowy"
      assert invoice.correction_type == 1
    end

    test "list_invoices filters by is_correction: true", %{company: company} do
      insert(:invoice, company: company, invoice_kind: :vat)
      insert(:correction_invoice, company: company)

      results = Invoices.list_invoices(company.id, %{is_correction: true})
      assert length(results) == 1
      assert hd(results).invoice_kind == :correction
    end

    test "list_invoices filters by is_correction: false", %{company: company} do
      insert(:invoice, company: company, invoice_kind: :vat)
      insert(:correction_invoice, company: company)

      results = Invoices.list_invoices(company.id, %{is_correction: false})
      assert length(results) == 1
      assert hd(results).invoice_kind == :vat
    end

    test "list_invoices filters by invoice_kind", %{company: company} do
      insert(:invoice, company: company, invoice_kind: :vat)
      insert(:correction_invoice, company: company)

      assert [%{invoice_kind: :correction}] =
               Invoices.list_invoices(company.id, %{invoice_kind: :correction})

      assert [%{invoice_kind: :vat}] =
               Invoices.list_invoices(company.id, %{invoice_kind: :vat})
    end

    test "link_unlinked_corrections links correction to original", %{company: company} do
      original =
        insert(:invoice,
          company: company,
          ksef_number: "7831812112-20260407-5B69FA00002B-9D"
        )

      correction =
        insert(:correction_invoice,
          company: company,
          corrected_invoice_ksef_number: "7831812112-20260407-5B69FA00002B-9D",
          corrects_invoice: nil
        )

      assert {1, nil} = Invoices.link_unlinked_corrections(company.id)

      updated = Invoices.get_invoice!(company.id, correction.id)
      assert updated.corrects_invoice_id == original.id
    end

    test "link_unlinked_corrections is idempotent", %{company: company} do
      original =
        insert(:invoice,
          company: company,
          ksef_number: "7831812112-20260407-5B69FA00002B-9D"
        )

      insert(:correction_invoice,
        company: company,
        corrected_invoice_ksef_number: "7831812112-20260407-5B69FA00002B-9D",
        corrects_invoice: original
      )

      assert {0, nil} = Invoices.link_unlinked_corrections(company.id)
    end

    test "link_unlinked_corrections does not cross companies", %{company: company} do
      other = insert(:company)

      insert(:invoice,
        company: other,
        ksef_number: "7831812112-20260407-5B69FA00002B-9D"
      )

      insert(:correction_invoice,
        company: company,
        corrected_invoice_ksef_number: "7831812112-20260407-5B69FA00002B-9D",
        corrects_invoice: nil
      )

      assert {0, nil} = Invoices.link_unlinked_corrections(company.id)
    end

    test "get_invoice_with_details! preloads corrections and corrects_invoice", %{
      company: company
    } do
      original =
        insert(:invoice,
          company: company,
          ksef_number: "7831812112-20260407-5B69FA00002B-9D"
        )

      correction =
        insert(:correction_invoice,
          company: company,
          corrected_invoice_ksef_number: "7831812112-20260407-5B69FA00002B-9D",
          corrects_invoice: original
        )

      # From the original's perspective: corrections are preloaded
      loaded_original = Invoices.get_invoice_with_details!(company.id, original.id)
      assert [%{id: correction_id}] = loaded_original.corrections
      assert correction_id == correction.id

      # From the correction's perspective: corrects_invoice is preloaded
      loaded_correction = Invoices.get_invoice_with_details!(company.id, correction.id)
      assert loaded_correction.corrects_invoice.id == original.id
    end
  end
end
