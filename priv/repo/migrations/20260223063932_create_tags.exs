defmodule KsefHub.Repo.Migrations.CreateTags do
  use Ecto.Migration

  def change do
    create table(:tags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :company_id, references(:companies, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create unique_index(:tags, [:company_id, :name])
    create index(:tags, [:company_id])

    create table(:invoice_tags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :invoice_id, references(:invoices, type: :binary_id, on_delete: :delete_all),
        null: false
      add :tag_id, references(:tags, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:invoice_tags, [:invoice_id, :tag_id])
    create index(:invoice_tags, [:tag_id])
  end
end
