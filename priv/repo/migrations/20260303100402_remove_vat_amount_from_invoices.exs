defmodule KsefHub.Repo.Migrations.RemoveVatAmountFromInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      remove :vat_amount, :decimal, precision: 15, scale: 2
    end
  end
end
