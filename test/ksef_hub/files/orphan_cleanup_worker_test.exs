defmodule KsefHub.Files.OrphanCleanupWorkerTest do
  use KsefHub.DataCase, async: true

  import Ecto.Query
  import KsefHub.Factory

  alias KsefHub.Files
  alias KsefHub.Files.OrphanCleanupWorker

  describe "perform/1" do
    test "deletes unreferenced files older than 24h" do
      old_file =
        insert(:file)
        |> set_inserted_at(hours_ago: 25)

      assert :ok = perform()

      assert_raise Ecto.NoResultsError, fn -> Files.get_file!(old_file.id) end
    end

    test "keeps referenced files (invoice xml_file)" do
      company = insert(:company)
      invoice = insert(:invoice, company: company)
      xml_file = invoice.xml_file

      set_inserted_at(xml_file, hours_ago: 48)

      assert :ok = perform()

      assert Files.get_file!(xml_file.id)
    end

    test "keeps referenced files (invoice pdf_file)" do
      company = insert(:company)
      pdf_file = insert(:file, content: "pdf", content_type: "application/pdf")

      insert(:pdf_upload_invoice, company: company, pdf_file: pdf_file)

      set_inserted_at(pdf_file, hours_ago: 48)

      assert :ok = perform()

      assert Files.get_file!(pdf_file.id)
    end

    test "keeps referenced files (inbound_email pdf_file)" do
      company = insert(:company)
      pdf_file = insert(:file, content: "pdf", content_type: "application/pdf")

      insert(:inbound_email, company: company, pdf_file: pdf_file)

      set_inserted_at(pdf_file, hours_ago: 48)

      assert :ok = perform()

      assert Files.get_file!(pdf_file.id)
    end

    test "keeps unreferenced files newer than 24h" do
      recent_file = insert(:file)

      assert :ok = perform()

      assert Files.get_file!(recent_file.id)
    end
  end

  @spec perform() :: :ok
  defp perform do
    OrphanCleanupWorker.perform(%Oban.Job{args: %{}})
  end

  @spec set_inserted_at(Files.File.t(), keyword()) :: Files.File.t()
  defp set_inserted_at(file, hours_ago: hours) do
    past = DateTime.utc_now() |> DateTime.add(-hours * 3600) |> DateTime.truncate(:microsecond)

    {1, _} =
      KsefHub.Repo.update_all(
        from(f in "files", where: f.id == ^Ecto.UUID.dump!(file.id)),
        set: [inserted_at: past]
      )

    file
  end
end
