defmodule KsefHub.Files.DataMigrationTest do
  use KsefHub.DataCase, async: true

  import Ecto.Query
  import KsefHub.Factory

  alias KsefHub.Files.DataMigration
  alias KsefHub.Repo

  defp dump_id!(id), do: Ecto.UUID.dump!(id)

  describe "run/0" do
    test "migrates invoice xml_content to files table" do
      company = insert(:company)
      invoice = insert(:invoice, company: company, xml_content: "<Faktura>test</Faktura>")

      # Ensure no xml_file_id yet
      row =
        Repo.one!(
          from(i in "invoices", where: i.id == ^dump_id!(invoice.id), select: i.xml_file_id)
        )

      assert is_nil(row)

      DataMigration.run()

      file_id_bin =
        Repo.one!(
          from(i in "invoices", where: i.id == ^dump_id!(invoice.id), select: i.xml_file_id)
        )

      assert file_id_bin != nil

      file_id = Ecto.UUID.load!(file_id_bin)
      file = Repo.get!(KsefHub.Files.File, file_id)
      assert file.content == "<Faktura>test</Faktura>"
      assert file.content_type == "application/xml"
      assert file.byte_size == byte_size("<Faktura>test</Faktura>")
    end

    test "migrates invoice pdf_content to files table" do
      company = insert(:company)
      pdf_binary = "%PDF-1.4 test content"

      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          pdf_content: pdf_binary,
          original_filename: "my_invoice.pdf"
        )

      DataMigration.run()

      file_id_bin =
        Repo.one!(
          from(i in "invoices", where: i.id == ^dump_id!(invoice.id), select: i.pdf_file_id)
        )

      assert file_id_bin != nil

      file_id = Ecto.UUID.load!(file_id_bin)
      file = Repo.get!(KsefHub.Files.File, file_id)
      assert file.content == pdf_binary
      assert file.content_type == "application/pdf"
      assert file.filename == "my_invoice.pdf"
    end

    test "migrates inbound_email pdf_content to files table" do
      company = insert(:company)
      pdf_binary = "%PDF-1.4 email attachment"

      email =
        insert(:inbound_email,
          company: company,
          pdf_content: pdf_binary,
          original_filename: "email_attachment.pdf"
        )

      DataMigration.run()

      file_id_bin =
        Repo.one!(
          from(ie in "inbound_emails",
            where: ie.id == ^dump_id!(email.id),
            select: ie.pdf_file_id
          )
        )

      assert file_id_bin != nil

      file_id = Ecto.UUID.load!(file_id_bin)
      file = Repo.get!(KsefHub.Files.File, file_id)
      assert file.content == pdf_binary
      assert file.content_type == "application/pdf"
      assert file.filename == "email_attachment.pdf"
    end

    test "skips rows that already have file IDs set (idempotent)" do
      company = insert(:company)

      existing_file =
        insert(:file, content: "<Faktura>old</Faktura>", content_type: "application/xml")

      invoice =
        insert(:invoice,
          company: company,
          xml_content: "<Faktura>test</Faktura>",
          xml_file: existing_file
        )

      initial_file_count = Repo.aggregate(KsefHub.Files.File, :count)

      DataMigration.run()

      # xml_file_id should remain unchanged
      file_id_bin =
        Repo.one!(
          from(i in "invoices", where: i.id == ^dump_id!(invoice.id), select: i.xml_file_id)
        )

      assert Ecto.UUID.load!(file_id_bin) == existing_file.id

      # No extra file was created
      assert Repo.aggregate(KsefHub.Files.File, :count) == initial_file_count
    end

    test "handles rows without content (nil content is skipped)" do
      company = insert(:company)
      _invoice = insert(:manual_invoice, company: company)

      initial_file_count = Repo.aggregate(KsefHub.Files.File, :count)

      DataMigration.run()

      assert Repo.aggregate(KsefHub.Files.File, :count) == initial_file_count
    end
  end
end
