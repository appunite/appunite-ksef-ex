defmodule KsefHub.Files.DataMigration do
  @moduledoc """
  Migrates existing inline content (xml_content, pdf_content) from invoices
  and inbound_emails into the files table. Idempotent — skips rows that
  already have file IDs set.
  """

  import Ecto.Query

  alias KsefHub.Repo

  @batch_size 100

  @doc "Runs the full data migration for all content types."
  @spec run() :: :ok
  def run do
    migrate_invoice_xml()
    migrate_invoice_pdf()
    migrate_inbound_email_pdf()
    :ok
  end

  @spec migrate_invoice_xml() :: :ok
  defp migrate_invoice_xml do
    "invoices"
    |> where([i], not is_nil(i.xml_content) and is_nil(i.xml_file_id))
    |> select([i], %{id: i.id, content: i.xml_content})
    |> stream_and_migrate("application/xml", "invoices", :xml_file_id)
  end

  @spec migrate_invoice_pdf() :: :ok
  defp migrate_invoice_pdf do
    "invoices"
    |> where([i], not is_nil(i.pdf_content) and is_nil(i.pdf_file_id))
    |> select([i], %{id: i.id, content: i.pdf_content, filename: i.original_filename})
    |> stream_and_migrate("application/pdf", "invoices", :pdf_file_id)
  end

  @spec migrate_inbound_email_pdf() :: :ok
  defp migrate_inbound_email_pdf do
    "inbound_emails"
    |> where([ie], not is_nil(ie.pdf_content) and is_nil(ie.pdf_file_id))
    |> select([ie], %{id: ie.id, content: ie.pdf_content, filename: ie.original_filename})
    |> stream_and_migrate("application/pdf", "inbound_emails", :pdf_file_id)
  end

  @spec stream_and_migrate(Ecto.Queryable.t(), String.t(), String.t(), atom()) :: :ok
  defp stream_and_migrate(query, content_type, table_name, fk_field) do
    query
    |> limit(@batch_size)
    |> migrate_batch(content_type, table_name, fk_field)
  end

  @spec migrate_batch(Ecto.Queryable.t(), String.t(), String.t(), atom()) :: :ok
  defp migrate_batch(query, content_type, table_name, fk_field) do
    batch = Repo.all(query)

    if batch == [] do
      :ok
    else
      {:ok, _} =
        Repo.transaction(fn ->
          Enum.each(batch, &migrate_row(&1, content_type, table_name, fk_field))
        end)

      # Fetch next batch (the WHERE clause filters already-migrated rows)
      migrate_batch(query, content_type, table_name, fk_field)
    end
  end

  @spec migrate_row(map(), String.t(), String.t(), atom()) :: :ok
  defp migrate_row(row, content_type, table_name, fk_field) do
    file_id = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {1, _} =
      Repo.insert_all("files", [
        %{
          id: Ecto.UUID.dump!(file_id),
          content: row.content,
          content_type: content_type,
          filename: Map.get(row, :filename),
          byte_size: byte_size(row.content),
          inserted_at: now
        }
      ])

    {1, _} =
      from(r in table_name, where: r.id == ^row.id)
      |> Repo.update_all(set: [{fk_field, Ecto.UUID.dump!(file_id)}])

    :ok
  end
end
