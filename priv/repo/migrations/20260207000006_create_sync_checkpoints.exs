defmodule KsefHub.Repo.Migrations.CreateSyncCheckpoints do
  use Ecto.Migration

  def change do
    create table(:sync_checkpoints, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :checkpoint_type, :string, null: false
      add :last_seen_timestamp, :utc_datetime_usec, null: false
      add :nip, :string, null: false
      add :metadata, :map, default: %{}

      timestamps()
    end

    create unique_index(:sync_checkpoints, [:checkpoint_type, :nip])
  end
end
