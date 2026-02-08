defmodule KsefHub.Repo.Migrations.AddCompanyIdToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict), null: false
    end

    # Drop old unique index on ksef_number
    drop_if_exists unique_index(:invoices, [:ksef_number])

    # New: unique ksef_number per company
    create unique_index(:invoices, [:company_id, :ksef_number])
    create index(:invoices, [:company_id])
  end
end
