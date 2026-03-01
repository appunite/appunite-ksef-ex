defmodule KsefHub.Repo.Migrations.PopulateFilesFromExistingContent do
  use Ecto.Migration

  def up do
    KsefHub.Files.DataMigration.run()
  end

  def down do
    # Data migration is not reversible — files remain in the table.
    # The FK columns will be nilified if the files table is dropped.
    :ok
  end
end
