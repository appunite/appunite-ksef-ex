defmodule KsefHub.Repo.Migrations.SimplifyTagsToStringArray do
  use Ecto.Migration

  def up do
    # 1. Add the new tags column as a string array
    alter table(:invoices) do
      add :tags, {:array, :string}, null: false, default: []
    end

    # Flush so the column exists before the data migration runs
    flush()

    # 2. Migrate existing tag data from the join table
    execute("""
    UPDATE invoices SET tags = subq.tag_names
    FROM (
      SELECT it.invoice_id, array_agg(t.name ORDER BY t.name) AS tag_names
      FROM invoice_tags it
      JOIN tags t ON t.id = it.tag_id
      GROUP BY it.invoice_id
    ) AS subq
    WHERE invoices.id = subq.invoice_id
    """)

    # 3. Add GIN index for efficient array queries
    create index(:invoices, [:tags], using: :gin)

    # 4. Drop join table first (FK dependency)
    drop table(:invoice_tags)

    # 5. Drop tags table
    drop table(:tags)
  end

  def down do
    create table(:tags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :type, :string, default: "expense"

      add :company_id, references(:companies, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create unique_index(:tags, [:company_id, :name, :type])

    create table(:invoice_tags, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :invoice_id, references(:invoices, type: :binary_id, on_delete: :delete_all),
        null: false

      add :tag_id, references(:tags, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:invoice_tags, [:invoice_id, :tag_id])

    drop index(:invoices, [:tags])

    alter table(:invoices) do
      remove :tags
    end
  end
end
