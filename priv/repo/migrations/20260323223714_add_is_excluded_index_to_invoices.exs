defmodule KsefHub.Repo.Migrations.AddIsExcludedIndexToInvoices do
  use Ecto.Migration

  def change do
    create index(:invoices, [:company_id, :is_excluded])
  end
end
