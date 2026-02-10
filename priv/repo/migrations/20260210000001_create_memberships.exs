defmodule KsefHub.Repo.Migrations.CreateMemberships do
  use Ecto.Migration

  def change do
    create table(:memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict), null: false

      timestamps()
    end

    create unique_index(:memberships, [:user_id, :company_id])
    create index(:memberships, [:company_id])
  end
end
