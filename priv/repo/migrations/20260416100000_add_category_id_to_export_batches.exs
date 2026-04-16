defmodule KsefHub.Repo.Migrations.AddCategoryIdToExportBatches do
  use Ecto.Migration

  def change do
    alter table(:export_batches) do
      add :category_id, references(:categories, type: :binary_id, on_delete: :nilify_all)
    end
  end
end
