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

    # The old index was on [:company_id, :name] but column was renamed above,
    # so we reference by the auto-generated index name.
    drop_if_exists index(:categories, [:company_id, :name],
                     name: "categories_company_id_name_index"
                   )

    create unique_index(:categories, [:company_id, :identifier])
  end
end
