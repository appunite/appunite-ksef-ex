defmodule KsefHub.Repo.Migrations.AddCostLine do
  use Ecto.Migration

  @valid_cost_lines ["growth", "heads", "service", "service_delivery", "client_success"]

  def up do
    alter table(:invoices) do
      add :cost_line, :string
    end

    alter table(:categories) do
      add :default_cost_line, :string
    end

    valid_sql = @valid_cost_lines |> Enum.map_join(", ", &"'#{&1}'")

    create constraint(:invoices, :invoices_cost_line_check,
             check: "cost_line IS NULL OR cost_line IN (#{valid_sql})"
           )

    create constraint(:categories, :categories_default_cost_line_check,
             check: "default_cost_line IS NULL OR default_cost_line IN (#{valid_sql})"
           )
  end

  def down do
    drop constraint(:invoices, :invoices_cost_line_check)
    drop constraint(:categories, :categories_default_cost_line_check)

    alter table(:invoices) do
      remove :cost_line
    end

    alter table(:categories) do
      remove :default_cost_line
    end
  end
end
