defmodule KsefHub.Repo.Migrations.DropLegacyContentColumns do
  @moduledoc """
  Drops inline content columns from invoices and inbound_emails.

  Depends on 20260301141405_populate_files_from_existing_content having
  migrated all data into the files table first. The down/0 recreates
  empty columns only — it does NOT restore data.
  """
  use Ecto.Migration

  def up do
    alter table(:invoices) do
      remove :xml_content
      remove :pdf_content
    end

    alter table(:inbound_emails) do
      remove :pdf_content
    end
  end

  def down do
    alter table(:invoices) do
      add :xml_content, :text
      add :pdf_content, :binary
    end

    alter table(:inbound_emails) do
      add :pdf_content, :binary
    end
  end
end
