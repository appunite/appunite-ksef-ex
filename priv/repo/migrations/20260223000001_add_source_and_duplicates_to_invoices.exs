defmodule KsefHub.Repo.Migrations.AddSourceAndDuplicatesToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :source, :string, null: false, default: "ksef"
      add :duplicate_of_id, references(:invoices, type: :binary_id, on_delete: :nilify_all)
      add :duplicate_status, :string

      # Reverse the NOT NULL constraint from migration 20260215000001
      modify :xml_content, :text, null: true, from: {:text, null: false}
    end

    # Drop the existing unique index on (company_id, ksef_number)
    drop unique_index(:invoices, [:company_id, :ksef_number])

    # Partial unique index: only enforce uniqueness for non-duplicate invoices
    create unique_index(:invoices, [:company_id, :ksef_number],
             where: "ksef_number IS NOT NULL AND duplicate_of_id IS NULL",
             name: :invoices_company_id_ksef_number_unique_non_duplicate
           )

    create index(:invoices, [:company_id, :source])
    create index(:invoices, [:duplicate_of_id])
  end
end
