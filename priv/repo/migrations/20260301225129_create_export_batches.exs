defmodule KsefHub.Repo.Migrations.CreateExportBatches do
  use Ecto.Migration

  def change do
    create table(:export_batches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "pending"
      add :date_from, :date, null: false
      add :date_to, :date, null: false
      add :invoice_type, :string
      add :only_new, :boolean, null: false, default: false
      add :invoice_count, :integer
      add :error_message, :string

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :company_id, references(:companies, type: :binary_id, on_delete: :delete_all),
        null: false

      add :zip_file_id, references(:files, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create index(:export_batches, [:company_id])
    create index(:export_batches, [:user_id])
    create index(:export_batches, [:status])

    create table(:invoice_downloads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :downloaded_at, :utc_datetime_usec, null: false

      add :invoice_id, references(:invoices, type: :binary_id, on_delete: :delete_all),
        null: false

      add :export_batch_id,
          references(:export_batches, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
    end

    create index(:invoice_downloads, [:invoice_id])
    create index(:invoice_downloads, [:export_batch_id])
    create unique_index(:invoice_downloads, [:invoice_id, :export_batch_id])
    create index(:invoice_downloads, [:user_id, :invoice_id])
  end
end
