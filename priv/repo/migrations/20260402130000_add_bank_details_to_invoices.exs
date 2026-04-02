defmodule KsefHub.Repo.Migrations.AddBankDetailsToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :swift_bic, :string, size: 11
      add :bank_name, :string, size: 255
      add :bank_address, :string, size: 500
      add :routing_number, :string, size: 9
      add :account_number, :string, size: 34
      add :payment_instructions, :text
    end
  end
end
