defmodule KsefHub.Invoices.DuplicateDetectorTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invoices.DuplicateDetector

  setup do
    company = insert(:company)
    %{company: company}
  end

  describe "detect/2" do
    test "returns attrs unchanged when no duplicate exists", %{company: company} do
      attrs = %{
        invoice_number: "FV/2026/001",
        issue_date: ~D[2026-01-15],
        net_amount: Decimal.new("500.00")
      }

      result = DuplicateDetector.detect(company.id, attrs)
      assert result == attrs
    end

    test "enriches attrs when duplicate found by KSeF number", %{company: company} do
      existing = insert(:invoice, ksef_number: "KSEF-DUP-1", company: company)

      attrs = %{ksef_number: "KSEF-DUP-1", invoice_number: "FV/X", issue_date: ~D[2026-01-01]}
      result = DuplicateDetector.detect(company.id, attrs)

      assert result[:duplicate_of_id] == existing.id
      assert result[:duplicate_status] == :suspected
    end

    test "enriches attrs when duplicate found by business fields", %{company: company} do
      existing =
        insert(:invoice,
          company: company,
          ksef_number: nil,
          invoice_number: "FV/BIZ/1",
          issue_date: ~D[2026-03-01],
          net_amount: Decimal.new("750.00"),
          seller_nip: "1111111111"
        )

      attrs = %{
        invoice_number: "FV/BIZ/1",
        issue_date: ~D[2026-03-01],
        net_amount: Decimal.new("750.00"),
        seller_nip: "1111111111"
      }

      result = DuplicateDetector.detect(company.id, attrs)
      assert result[:duplicate_of_id] == existing.id
      assert result[:duplicate_status] == :suspected
    end
  end

  describe "find_original_id/3" do
    test "returns nil when no match", %{company: company} do
      assert is_nil(DuplicateDetector.find_original_id(company.id, %{ksef_number: "NOPE"}))
    end

    test "excludes the invoice's own ID", %{company: company} do
      existing = insert(:invoice, ksef_number: "KSEF-SELF", company: company)

      assert is_nil(
               DuplicateDetector.find_original_id(company.id, %{ksef_number: "KSEF-SELF"},
                 exclude_id: existing.id
               )
             )
    end

    test "skips invoices already marked as duplicates", %{company: company} do
      original = insert(:invoice, ksef_number: "KSEF-ORIG", company: company)

      _dup =
        insert(:invoice,
          ksef_number: "KSEF-ORIG",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      assert DuplicateDetector.find_original_id(company.id, %{ksef_number: "KSEF-ORIG"}) ==
               original.id
    end
  end

  describe "find_original_id/3 with invalid types" do
    test "returns nil when issue_date is an unparseable string", %{company: company} do
      insert(:invoice,
        company: company,
        ksef_number: nil,
        invoice_number: "FV/BAD/1",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100.00")
      )

      attrs = %{
        invoice_number: "FV/BAD/1",
        issue_date: "not-a-date",
        net_amount: Decimal.new("100.00")
      }

      assert is_nil(DuplicateDetector.find_original_id(company.id, attrs))
    end

    test "returns nil when net_amount is an unparseable string", %{company: company} do
      insert(:invoice,
        company: company,
        ksef_number: nil,
        invoice_number: "FV/BAD/2",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100.00")
      )

      attrs = %{
        invoice_number: "FV/BAD/2",
        issue_date: ~D[2026-01-01],
        net_amount: "not-a-number"
      }

      assert is_nil(DuplicateDetector.find_original_id(company.id, attrs))
    end

    test "returns nil when issue_date is nil", %{company: company} do
      insert(:invoice,
        company: company,
        ksef_number: nil,
        invoice_number: "FV/NIL/1",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100.00")
      )

      attrs = %{invoice_number: "FV/NIL/1", issue_date: nil, net_amount: Decimal.new("100.00")}
      assert is_nil(DuplicateDetector.find_original_id(company.id, attrs))
    end

    test "returns nil when net_amount is nil", %{company: company} do
      insert(:invoice,
        company: company,
        ksef_number: nil,
        invoice_number: "FV/NIL/2",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100.00")
      )

      attrs = %{invoice_number: "FV/NIL/2", issue_date: ~D[2026-01-01], net_amount: nil}
      assert is_nil(DuplicateDetector.find_original_id(company.id, attrs))
    end

    test "returns nil when invoice_number is missing", %{company: company} do
      attrs = %{issue_date: ~D[2026-01-01], net_amount: Decimal.new("100.00")}
      assert is_nil(DuplicateDetector.find_original_id(company.id, attrs))
    end

    test "handles issue_date as ISO8601 string", %{company: company} do
      existing =
        insert(:invoice,
          company: company,
          ksef_number: nil,
          invoice_number: "FV/STR/1",
          issue_date: ~D[2026-06-15],
          net_amount: Decimal.new("200.00")
        )

      attrs = %{
        invoice_number: "FV/STR/1",
        issue_date: "2026-06-15",
        net_amount: Decimal.new("200.00")
      }

      assert DuplicateDetector.find_original_id(company.id, attrs) == existing.id
    end

    test "handles net_amount as string", %{company: company} do
      existing =
        insert(:invoice,
          company: company,
          ksef_number: nil,
          invoice_number: "FV/STR/2",
          issue_date: ~D[2026-06-15],
          net_amount: Decimal.new("300.00")
        )

      attrs = %{
        invoice_number: "FV/STR/2",
        issue_date: ~D[2026-06-15],
        net_amount: "300.00"
      }

      assert DuplicateDetector.find_original_id(company.id, attrs) == existing.id
    end

    test "handles string-keyed attrs", %{company: company} do
      existing =
        insert(:invoice,
          company: company,
          ksef_number: nil,
          invoice_number: "FV/STRKEY/1",
          issue_date: ~D[2026-07-01],
          net_amount: Decimal.new("400.00")
        )

      attrs = %{
        "invoice_number" => "FV/STRKEY/1",
        "issue_date" => "2026-07-01",
        "net_amount" => "400.00"
      }

      assert DuplicateDetector.find_original_id(company.id, attrs) == existing.id
    end
  end

  describe "business field matching rules" do
    test "both have different KSeF numbers — not duplicate", %{company: company} do
      insert(:invoice,
        company: company,
        ksef_number: "KSEF-A",
        invoice_number: "FV/SAME/1",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100.00")
      )

      attrs = %{
        ksef_number: "KSEF-B",
        invoice_number: "FV/SAME/1",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100.00")
      }

      assert is_nil(DuplicateDetector.find_original_id(company.id, attrs))
    end

    test "new has KSeF number, candidate does not — matches", %{company: company} do
      existing =
        insert(:invoice,
          company: company,
          ksef_number: nil,
          invoice_number: "FV/CROSS/1",
          issue_date: ~D[2026-02-01],
          net_amount: Decimal.new("500.00")
        )

      attrs = %{
        ksef_number: "KSEF-NEW",
        invoice_number: "FV/CROSS/1",
        issue_date: ~D[2026-02-01],
        net_amount: Decimal.new("500.00")
      }

      assert DuplicateDetector.find_original_id(company.id, attrs) == existing.id
    end

    test "different seller_nip — not duplicate", %{company: company} do
      insert(:invoice,
        company: company,
        ksef_number: nil,
        invoice_number: "FV/NIP/1",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100.00"),
        seller_nip: "1111111111"
      )

      attrs = %{
        invoice_number: "FV/NIP/1",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100.00"),
        seller_nip: "2222222222"
      }

      assert is_nil(DuplicateDetector.find_original_id(company.id, attrs))
    end

    test "no seller_nip on new invoice — still matches (non-EU)", %{company: company} do
      existing =
        insert(:invoice,
          company: company,
          ksef_number: nil,
          invoice_number: "FV/NOEU/1",
          issue_date: ~D[2026-01-01],
          net_amount: Decimal.new("100.00"),
          seller_nip: nil
        )

      attrs = %{
        invoice_number: "FV/NOEU/1",
        issue_date: ~D[2026-01-01],
        net_amount: Decimal.new("100.00"),
        seller_nip: nil
      }

      assert DuplicateDetector.find_original_id(company.id, attrs) == existing.id
    end
  end
end
