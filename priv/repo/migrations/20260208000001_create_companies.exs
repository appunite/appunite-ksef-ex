defmodule KsefHub.Repo.Migrations.CreateCompanies do
  use Ecto.Migration

  def change do
    create table(:companies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :nip, :string, null: false
      add :address, :string
      add :is_active, :boolean, default: true, null: false

      timestamps()
    end

    create unique_index(:companies, [:nip])
  end
end
