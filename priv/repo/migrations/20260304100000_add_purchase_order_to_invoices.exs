defmodule KsefHub.Repo.Migrations.AddPurchaseOrderToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :purchase_order, :string, size: 256
    end
  end
end
