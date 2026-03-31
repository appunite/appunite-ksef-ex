defmodule KsefHub.Repo.Migrations.AddCostLine do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :cost_line, :string
    end

    alter table(:categories) do
      add :default_cost_line, :string
    end
  end
end
