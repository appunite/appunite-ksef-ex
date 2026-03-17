defmodule KsefHub.Repo.Migrations.AddTypeToTags do
  use Ecto.Migration

  def change do
    alter table(:tags) do
      add :type, :string, null: false, default: "expense"
    end

    create constraint(:tags, :tags_type_must_be_valid, check: "type IN ('expense')")

    drop unique_index(:tags, [:company_id, :name])
    create unique_index(:tags, [:company_id, :name, :type])
    create index(:tags, [:company_id, :type])
  end
end
