defmodule KsefHub.Repo.Migrations.CreateCompanyBankAccounts do
  use Ecto.Migration

  def change do
    create table(:company_bank_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :company_id, references(:companies, type: :binary_id, on_delete: :delete_all),
        null: false

      add :currency, :string, null: false
      add :iban, :string, null: false
      add :label, :string

      timestamps()
    end

    create unique_index(:company_bank_accounts, [:company_id, :currency])
  end
end
