defmodule KsefHub.Repo.Migrations.AddTypeToTags do
  use Ecto.Migration

  def change do
    alter table(:tags) do
      add :type, :string, null: false, default: "expense"
    end

    drop unique_index(:tags, [:company_id, :name])
    create unique_index(:tags, [:company_id, :name, :type])
  end
end
