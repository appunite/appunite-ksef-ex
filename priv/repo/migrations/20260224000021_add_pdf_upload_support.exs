defmodule KsefHub.Repo.Migrations.AddPdfUploadSupport do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :pdf_content, :binary
      add :extraction_status, :string
      add :original_filename, :string, size: 255
    end

    create index(:invoices, [:extraction_status], where: "extraction_status IS NOT NULL")
  end
end
