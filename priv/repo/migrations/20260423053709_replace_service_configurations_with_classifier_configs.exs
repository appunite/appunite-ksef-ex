defmodule KsefHub.Repo.Migrations.ReplaceServiceConfigurationsWithClassifierConfigs do
  use Ecto.Migration

  def up do
    drop table(:service_configurations)

    create table(:classifier_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :company_id, references(:companies, type: :binary_id, on_delete: :delete_all),
        null: false

      add :enabled, :boolean, default: false, null: false
      add :url, :string
      add :api_token_encrypted, :binary
      add :category_confidence_threshold, :float
      add :tag_confidence_threshold, :float
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:classifier_configs, [:company_id])
  end

  def down do
    drop table(:classifier_configs)

    create table(:service_configurations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :service_name, :string, null: false
      add :url, :string, null: false
      add :api_token_encrypted, :binary
      add :settings, :map, default: %{}, null: false
      add :enabled, :boolean, default: true, null: false
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:service_configurations, [:service_name])
  end
end
