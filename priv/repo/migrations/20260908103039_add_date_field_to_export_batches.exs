defmodule KsefHub.Repo.Migrations.AddDateFieldToExportBatches do
  use Ecto.Migration

  @moduledoc """
  Records which invoice date column an export batch ranges over.

  The export runs asynchronously in an Oban worker that reads the batch back
  from the database, so the choice has to be persisted rather than passed
  through. Existing batches were all issue-date exports, which the default
  backfills.
  """

  def change do
    alter table(:export_batches) do
      add :date_field, :string, null: false, default: "issue"
    end
  end
end
