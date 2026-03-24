defmodule KsefHub.Repo.Migrations.AddInvoiceAccessControl do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :access_restricted, :boolean, default: false, null: false
    end

    create table(:invoice_access_grants, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :invoice_id, references(:invoices, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :granted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps()
    end

    create unique_index(:invoice_access_grants, [:invoice_id, :user_id])
    create index(:invoice_access_grants, [:user_id])
  end
end
