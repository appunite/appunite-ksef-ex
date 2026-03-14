defmodule KsefHub.Repo.Migrations.CreatePaymentRequestCsvDownloads do
  use Ecto.Migration

  def change do
    create table(:payment_request_csv_downloads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :payment_request_ids, {:array, :binary_id}, null: false
      add :downloaded_at, :utc_datetime_usec, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false

      add :company_id, references(:companies, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    create index(:payment_request_csv_downloads, [:company_id, :downloaded_at])
  end
end
