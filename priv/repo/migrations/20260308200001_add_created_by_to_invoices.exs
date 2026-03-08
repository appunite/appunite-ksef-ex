defmodule KsefHub.Repo.Migrations.AddCreatedByToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:invoices, [:created_by_id])
  end
end
