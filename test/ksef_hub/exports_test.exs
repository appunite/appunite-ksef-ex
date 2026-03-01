defmodule KsefHub.ExportsTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Exports
  alias KsefHub.Exports.{ExportBatch, InvoiceDownload}

  setup do
    user = insert(:user)
    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)
    %{user: user, company: company}
  end

  describe "create_export/3" do
    test "creates a pending batch with valid params", %{user: user, company: company} do
      params = %{
        date_from: "2026-01-01",
        date_to: "2026-01-31",
        invoice_type: "expense",
        only_new: false
      }

      assert {:ok, batch} = Exports.create_export(user.id, company.id, params)
      assert batch.status == :pending
      assert batch.date_from == ~D[2026-01-01]
      assert batch.date_to == ~D[2026-01-31]
      assert batch.invoice_type == "expense"
      assert batch.only_new == false
      assert batch.user_id == user.id
      assert batch.company_id == company.id
    end

    test "rejects date range exceeding 31 days", %{user: user, company: company} do
      params = %{
        date_from: "2026-01-01",
        date_to: "2026-03-01",
        invoice_type: nil,
        only_new: false
      }

      assert {:error, changeset} = Exports.create_export(user.id, company.id, params)
      assert errors_on(changeset)[:date_to] != nil
    end

    test "rejects date_to before date_from", %{user: user, company: company} do
      params = %{
        date_from: "2026-02-01",
        date_to: "2026-01-01",
        invoice_type: nil,
        only_new: false
      }

      assert {:error, changeset} = Exports.create_export(user.id, company.id, params)
      assert errors_on(changeset)[:date_to] != nil
    end

    test "allows nil invoice_type (all types)", %{user: user, company: company} do
      params = %{
        date_from: "2026-01-01",
        date_to: "2026-01-31",
        invoice_type: nil,
        only_new: false
      }

      assert {:ok, batch} = Exports.create_export(user.id, company.id, params)
      assert batch.invoice_type == nil
    end
  end

  describe "count_exportable_invoices/2" do
    test "counts approved invoices in date range", %{user: user, company: company} do
      insert(:invoice,
        company: company,
        issue_date: ~D[2026-01-15],
        type: :expense,
        status: :approved
      )

      insert(:invoice,
        company: company,
        issue_date: ~D[2026-01-20],
        type: :income,
        status: :approved
      )

      insert(:invoice,
        company: company,
        issue_date: ~D[2026-02-05],
        type: :expense,
        status: :approved
      )

      count =
        Exports.count_exportable_invoices(company.id, %{
          date_from: ~D[2026-01-01],
          date_to: ~D[2026-01-31],
          invoice_type: nil,
          only_new: false,
          user_id: user.id
        })

      assert count == 2
    end

    test "filters by invoice type", %{user: user, company: company} do
      insert(:invoice,
        company: company,
        issue_date: ~D[2026-01-15],
        type: :expense,
        status: :approved
      )

      insert(:invoice,
        company: company,
        issue_date: ~D[2026-01-20],
        type: :income,
        status: :approved
      )

      count =
        Exports.count_exportable_invoices(company.id, %{
          date_from: ~D[2026-01-01],
          date_to: ~D[2026-01-31],
          invoice_type: "expense",
          only_new: false,
          user_id: user.id
        })

      assert count == 1
    end

    test "only_new excludes previously downloaded invoices", %{user: user, company: company} do
      inv1 =
        insert(:invoice,
          company: company,
          issue_date: ~D[2026-01-15],
          type: :expense,
          status: :approved
        )

      insert(:invoice,
        company: company,
        issue_date: ~D[2026-01-20],
        type: :expense,
        status: :approved
      )

      batch = insert(:export_batch, user: user, company: company)
      insert(:invoice_download, invoice: inv1, export_batch: batch, user: user)

      count =
        Exports.count_exportable_invoices(company.id, %{
          date_from: ~D[2026-01-01],
          date_to: ~D[2026-01-31],
          invoice_type: nil,
          only_new: true,
          user_id: user.id
        })

      assert count == 1
    end

    test "excludes pending and rejected invoices", %{user: user, company: company} do
      insert(:invoice,
        company: company,
        issue_date: ~D[2026-01-15],
        type: :expense,
        status: :approved
      )

      insert(:invoice,
        company: company,
        issue_date: ~D[2026-01-16],
        type: :expense,
        status: :pending
      )

      insert(:invoice,
        company: company,
        issue_date: ~D[2026-01-17],
        type: :expense,
        status: :rejected
      )

      count =
        Exports.count_exportable_invoices(company.id, %{
          date_from: ~D[2026-01-01],
          date_to: ~D[2026-01-31],
          invoice_type: nil,
          only_new: false,
          user_id: user.id
        })

      assert count == 1
    end

    test "only_new is per-user", %{user: user, company: company} do
      other_user = insert(:user)

      inv =
        insert(:invoice,
          company: company,
          issue_date: ~D[2026-01-15],
          type: :expense,
          status: :approved
        )

      batch = insert(:export_batch, user: other_user, company: company)
      insert(:invoice_download, invoice: inv, export_batch: batch, user: other_user)

      # user should still see this invoice as "new"
      count =
        Exports.count_exportable_invoices(company.id, %{
          date_from: ~D[2026-01-01],
          date_to: ~D[2026-01-31],
          invoice_type: nil,
          only_new: true,
          user_id: user.id
        })

      assert count == 1
    end
  end

  describe "list_batches/2" do
    test "returns batches for user in company", %{user: user, company: company} do
      insert(:export_batch, user: user, company: company)
      insert(:export_batch, user: user, company: company)
      other_user = insert(:user)
      insert(:export_batch, user: other_user, company: company)

      batches = Exports.list_batches(company.id, user.id)
      assert length(batches) == 2
    end

    test "returns batches for user in correct company", %{user: user, company: company} do
      insert(:export_batch, user: user, company: company, date_from: ~D[2026-01-01])

      other_company = insert(:company)
      insert(:export_batch, user: user, company: other_company, date_from: ~D[2026-02-01])

      batches = Exports.list_batches(company.id, user.id)
      assert length(batches) == 1
      assert hd(batches).company_id == company.id
    end
  end

  describe "get_batch_with_file!/3" do
    test "returns batch with preloaded zip_file", %{user: user, company: company} do
      file = insert(:file, content: "zip-data", content_type: "application/zip")

      batch =
        insert(:export_batch, user: user, company: company, zip_file: file, status: :completed)

      result = Exports.get_batch_with_file!(company.id, user.id, batch.id)
      assert result.id == batch.id
      assert result.zip_file.content == "zip-data"
    end

    test "raises for non-existent batch", %{user: user, company: company} do
      assert_raise Ecto.NoResultsError, fn ->
        Exports.get_batch_with_file!(company.id, user.id, Ecto.UUID.generate())
      end
    end

    test "raises for batch in different company", %{user: user, company: company} do
      other_company = insert(:company)
      batch = insert(:export_batch, user: user, company: other_company)

      assert_raise Ecto.NoResultsError, fn ->
        Exports.get_batch_with_file!(company.id, user.id, batch.id)
      end
    end

    test "raises for batch owned by different user", %{user: user, company: company} do
      other_user = insert(:user)
      batch = insert(:export_batch, user: other_user, company: company)

      assert_raise Ecto.NoResultsError, fn ->
        Exports.get_batch_with_file!(company.id, user.id, batch.id)
      end
    end
  end

  describe "resolve_pdf/1" do
    test "returns pdf_file content when available" do
      invoice =
        struct!(KsefHub.Invoices.Invoice, %{
          pdf_file: %{content: "pdf-data"},
          xml_file: nil
        })

      assert {:ok, "pdf-data"} = Exports.resolve_pdf(invoice)
    end

    test "returns error when no source content" do
      invoice =
        struct!(KsefHub.Invoices.Invoice, %{
          pdf_file: nil,
          xml_file: nil
        })

      assert {:error, :no_source_content} = Exports.resolve_pdf(invoice)
    end
  end

  describe "generate_export/1" do
    test "generates ZIP with CSV and updates batch to completed", %{
      user: user,
      company: company
    } do
      Mox.stub(KsefHub.PdfRenderer.Mock, :generate_pdf, fn _xml, _meta ->
        {:ok, "fake-pdf-binary"}
      end)

      insert(:invoice,
        company: company,
        issue_date: ~D[2026-01-15],
        type: :expense,
        status: :approved
      )

      insert(:manual_invoice,
        company: company,
        issue_date: ~D[2026-01-20],
        type: :expense,
        status: :approved
      )

      batch =
        insert(:export_batch,
          user: user,
          company: company,
          date_from: ~D[2026-01-01],
          date_to: ~D[2026-01-31],
          invoice_type: "expense"
        )

      assert :ok = Exports.generate_export(batch)

      updated = Repo.get!(ExportBatch, batch.id)
      assert updated.status == :completed
      assert updated.invoice_count == 2
      assert updated.zip_file_id != nil

      downloads = Repo.all(InvoiceDownload)
      assert length(downloads) == 2
    end

    test "completes successfully with zero invoices", %{user: user, company: company} do
      batch =
        insert(:export_batch,
          user: user,
          company: company,
          date_from: ~D[2026-01-01],
          date_to: ~D[2026-01-31]
        )

      assert :ok = Exports.generate_export(batch)

      updated = Repo.get!(ExportBatch, batch.id)
      assert updated.status == :completed
      assert updated.invoice_count == 0
    end
  end
end
