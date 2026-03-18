defmodule KsefHub.Repo.Migrations.ExtendCategories do
  use Ecto.Migration

  def change do
    rename table(:categories), :name, to: :identifier

    alter table(:categories) do
      add :name, :string
      add :examples, :text
    end

    drop unique_index(:categories, [:company_id, :name])
    create unique_index(:categories, [:company_id, :identifier])
  end
end
