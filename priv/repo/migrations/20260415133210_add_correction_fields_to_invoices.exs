defmodule KsefHub.Repo.Migrations.AddCorrectionFieldsToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :invoice_kind, :string, default: "vat", null: false
      add :corrected_invoice_number, :string
      add :corrected_invoice_ksef_number, :string
      add :corrected_invoice_date, :date
      add :correction_period_from, :date
      add :correction_period_to, :date
      add :correction_reason, :string
      add :correction_type, :integer

      add :corrects_invoice_id,
          references(:invoices, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:invoices, [:corrects_invoice_id])
    create index(:invoices, [:company_id, :invoice_kind])
  end
end
