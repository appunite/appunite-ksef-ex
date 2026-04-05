defmodule KsefHub.Repo.Migrations.AddAutoApproveToCompanies do
  use Ecto.Migration

  def change do
    alter table(:companies) do
      add :auto_approve_trusted_invoices, :boolean, default: false, null: false
    end
  end
end
