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

    execute(
      "CREATE INDEX invoices_iban_trgm_idx ON invoices USING gin (iban gin_trgm_ops)",
      "DROP INDEX IF EXISTS invoices_iban_trgm_idx"
    )
  end
end
