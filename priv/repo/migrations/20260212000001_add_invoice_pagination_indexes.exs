defmodule KsefHub.Repo.Migrations.AddInvoicePaginationIndexes do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    # Compound index for default ORDER BY (company_id, issue_date DESC, inserted_at DESC)
    create index(:invoices, [:company_id, :issue_date, :inserted_at],
             name: :invoices_company_date_idx
           )

    # Compound index for filtered listings by type and status
    create index(:invoices, [:company_id, :type, :status],
             name: :invoices_company_type_status_idx
           )

    # GIN trigram indexes for ILIKE search
    execute(
      "CREATE INDEX invoices_invoice_number_trgm_idx ON invoices USING gin (invoice_number gin_trgm_ops)"
    )

    execute(
      "CREATE INDEX invoices_seller_name_trgm_idx ON invoices USING gin (seller_name gin_trgm_ops)"
    )

    execute(
      "CREATE INDEX invoices_buyer_name_trgm_idx ON invoices USING gin (buyer_name gin_trgm_ops)"
    )
  end

  def down do
    execute("DROP INDEX IF EXISTS invoices_buyer_name_trgm_idx")
    execute("DROP INDEX IF EXISTS invoices_seller_name_trgm_idx")
    execute("DROP INDEX IF EXISTS invoices_invoice_number_trgm_idx")

    drop_if_exists index(:invoices, [:company_id, :type, :status],
                     name: :invoices_company_type_status_idx
                   )

    drop_if_exists index(:invoices, [:company_id, :issue_date, :inserted_at],
                     name: :invoices_company_date_idx
                   )

    execute("DROP EXTENSION IF EXISTS pg_trgm")
  end
end
