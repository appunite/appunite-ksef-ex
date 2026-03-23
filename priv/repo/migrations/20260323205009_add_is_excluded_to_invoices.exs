defmodule KsefHub.Repo.Migrations.AddIsExcludedToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :is_excluded, :boolean, default: false, null: false
    end
  end
end
