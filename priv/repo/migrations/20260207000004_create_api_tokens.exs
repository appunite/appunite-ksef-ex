defmodule KsefHub.Repo.Migrations.CreateApiTokens do
  use Ecto.Migration

  def change do
    create table(:api_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :token_hash, :string, null: false
      add :token_prefix, :string, null: false
      add :last_used_at, :utc_datetime_usec
      add :request_count, :integer, default: 0, null: false
      add :is_active, :boolean, default: true, null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:api_tokens, [:token_hash])
    create index(:api_tokens, [:created_by_id])
    create index(:api_tokens, [:is_active])
  end
end
