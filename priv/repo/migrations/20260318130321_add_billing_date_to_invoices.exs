defmodule KsefHub.Repo.Migrations.AddBillingDateToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :billing_date, :date
    end

    create index(:invoices, [:company_id, :billing_date])

    execute(
      """
      UPDATE invoices
      SET billing_date = date_trunc('month', COALESCE(sales_date, issue_date))::date
      WHERE COALESCE(sales_date, issue_date) IS NOT NULL
      """,
      "UPDATE invoices SET billing_date = NULL"
    )
  end
end
