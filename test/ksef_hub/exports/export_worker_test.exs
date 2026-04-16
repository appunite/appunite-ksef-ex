defmodule KsefHub.Exports.ExportWorkerTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Exports.{ExportBatch, ExportWorker}

  setup do
    Mox.stub(KsefHub.PdfRenderer.Mock, :generate_pdf, fn _xml, _meta ->
      {:ok, "fake-pdf-binary"}
    end)

    user = insert(:user)
    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)
    %{user: user, company: company}
  end

  describe "perform/1" do
    test "generates export for valid batch", %{user: user, company: company} do
      insert(:invoice,
        company: company,
        issue_date: ~D[2026-01-15],
        type: :expense,
        expense_approval_status: :approved
      )

      batch =
        insert(:export_batch,
          user: user,
          company: company,
          date_from: ~D[2026-01-01],
          date_to: ~D[2026-01-31],
          invoice_type: "expense"
        )

      assert :ok =
               ExportWorker.perform(%Oban.Job{args: %{"export_batch_id" => batch.id}})

      updated = Repo.get!(ExportBatch, batch.id)
      assert updated.status == :completed
      assert updated.invoice_count == 1
    end

    test "cancels for non-existent batch" do
      assert {:cancel, "export batch not found"} =
               ExportWorker.perform(%Oban.Job{
                 args: %{"export_batch_id" => Ecto.UUID.generate()}
               })
    end

    test "cancels for already completed batch", %{user: user, company: company} do
      batch = insert(:export_batch, user: user, company: company, status: :completed)

      assert {:cancel, "export batch already completed"} =
               ExportWorker.perform(%Oban.Job{args: %{"export_batch_id" => batch.id}})
    end

    test "cancels for already failed batch", %{user: user, company: company} do
      batch = insert(:export_batch, user: user, company: company, status: :failed)

      assert {:cancel, "export batch already failed"} =
               ExportWorker.perform(%Oban.Job{args: %{"export_batch_id" => batch.id}})
    end
  end
end
