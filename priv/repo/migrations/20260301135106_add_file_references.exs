defmodule KsefHub.Repo.Migrations.AddFileReferences do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :xml_file_id, references(:files, type: :binary_id, on_delete: :nilify_all)
      add :pdf_file_id, references(:files, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:inbound_emails) do
      add :pdf_file_id, references(:files, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:invoices, [:xml_file_id])
    create index(:invoices, [:pdf_file_id])
    create index(:inbound_emails, [:pdf_file_id])
  end
end
