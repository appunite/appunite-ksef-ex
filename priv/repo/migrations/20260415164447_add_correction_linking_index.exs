defmodule KsefHub.Repo.Migrations.AddCorrectionLinkingIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:invoices, [:company_id, :corrected_invoice_ksef_number],
             where: "corrected_invoice_ksef_number IS NOT NULL AND corrects_invoice_id IS NULL",
             concurrently: true
           )
  end
end
