defmodule KsefHub.Repo.Migrations.ExtendCategories do
  use Ecto.Migration

  @doc """
  Splits the old `name` column (which held the ML classifier key, e.g. "finance:invoices")
  into `identifier` (ML key) + a new `name` column for human-readable display.
  Also adds `examples` for category context used by emoji generation.
  """
  def change do
    rename table(:categories), :name, to: :identifier

    alter table(:categories) do
      add :name, :string
      add :examples, :text
    end

    drop unique_index(:categories, [:company_id, :name])
    create unique_index(:categories, [:company_id, :identifier])
  end
end
