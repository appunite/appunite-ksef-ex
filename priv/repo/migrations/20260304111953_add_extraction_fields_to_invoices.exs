defmodule KsefHub.Repo.Migrations.AddExtractionFieldsToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :sales_date, :date
      add :due_date, :date
      add :iban, :string, size: 34
      add :seller_address, :map
      add :buyer_address, :map
    end
  end
end
