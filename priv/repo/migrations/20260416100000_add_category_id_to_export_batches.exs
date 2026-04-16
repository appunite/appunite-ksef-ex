defmodule KsefHub.Repo.Migrations.AddCategoryIdToExportBatches do
  @moduledoc """
  Adds a nullable `category_id` foreign key to `export_batches`, allowing an
  export to be scoped to a specific expense category.
  """

  use Ecto.Migration

  @doc "Adds the `category_id` column referencing `categories`."
  @spec change() :: any()
  def change do
    alter table(:export_batches) do
      add :category_id, references(:categories, type: :binary_id, on_delete: :nilify_all)
    end
  end
end
