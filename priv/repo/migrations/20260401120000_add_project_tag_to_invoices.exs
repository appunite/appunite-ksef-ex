defmodule KsefHub.Repo.Migrations.AddProjectTagToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :project_tag, :string
    end

    create index(:invoices, [:company_id, :project_tag])
  end
end
