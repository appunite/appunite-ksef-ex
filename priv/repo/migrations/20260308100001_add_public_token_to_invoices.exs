defmodule KsefHub.Repo.Migrations.AddPublicTokenToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :public_token, :string, size: 44
    end

    create unique_index(:invoices, [:public_token], where: "public_token IS NOT NULL")
  end
end
