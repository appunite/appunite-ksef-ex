defmodule KsefHub.Repo.Migrations.DropLegacyContentColumns do
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
