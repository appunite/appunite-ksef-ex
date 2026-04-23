defmodule KsefHub.Repo.Migrations.CreateServiceConfigurations do
  use Ecto.Migration

  def change do
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

    flush()

    execute(
      """
      INSERT INTO service_configurations (id, service_name, url, settings, enabled, inserted_at, updated_at)
      VALUES
        (gen_random_uuid(), 'pdf_renderer', 'http://localhost:3001', '{}', false, NOW(), NOW()),
        (gen_random_uuid(), 'invoice_extractor', 'http://localhost:3002', '{}', false, NOW(), NOW()),
        (gen_random_uuid(), 'invoice_classifier', 'http://localhost:3003',
         '{"category_confidence_threshold": 0.71, "tag_confidence_threshold": 0.95}', false, NOW(), NOW())
      """,
      """
      DELETE FROM service_configurations
      WHERE service_name IN ('pdf_renderer', 'invoice_extractor', 'invoice_classifier')
      """
    )
  end
end
