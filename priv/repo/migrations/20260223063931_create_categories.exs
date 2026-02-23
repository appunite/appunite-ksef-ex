defmodule KsefHub.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :emoji, :string
      add :description, :string
      add :sort_order, :integer, null: false, default: 0

      add :company_id, references(:companies, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create unique_index(:categories, [:company_id, :name])
    create index(:categories, [:company_id, :sort_order])

    alter table(:invoices) do
      add :category_id, references(:categories, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:invoices, [:category_id])
  end
end
