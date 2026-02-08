defmodule KsefHub.Repo.Migrations.AddCompanyIdToCheckpoints do
  use Ecto.Migration

  def change do
    alter table(:sync_checkpoints) do
      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict), null: false
      modify :nip, :string, null: true
    end

    # Drop old unique index on (checkpoint_type, nip)
    drop_if_exists unique_index(:sync_checkpoints, [:checkpoint_type, :nip])

    # New: unique per (checkpoint_type, company_id)
    create unique_index(:sync_checkpoints, [:checkpoint_type, :company_id])
    create index(:sync_checkpoints, [:company_id])
  end
end
