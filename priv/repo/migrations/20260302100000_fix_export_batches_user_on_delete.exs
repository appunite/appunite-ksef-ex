defmodule KsefHub.Repo.Migrations.FixExportBatchesUserOnDelete do
  use Ecto.Migration

  def change do
    execute(
      "ALTER TABLE export_batches DROP CONSTRAINT IF EXISTS export_batches_user_id_fkey",
      "SELECT 1"
    )

    alter table(:export_batches) do
      modify :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
    end
  end
end
