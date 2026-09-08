defmodule KsefHub.Repo.Migrations.AddSaleDateIndexToInvoices do
  use Ecto.Migration

  @moduledoc """
  Indexes the effective sale date so sale-date ranges are servable by an index.

  Invoice list filters and exports range over `coalesce(sales_date, issue_date)`
  when the user picks the sale date. Wrapping the column in a function makes the
  predicate unsargable, so neither `invoices_company_date_idx` nor
  `invoices_issue_date_index` can serve it — this expression index restores what
  the issue-date path already had.
  """

  def change do
    create index(:invoices, ["company_id", "coalesce(sales_date, issue_date)"],
             name: :invoices_company_sale_date_idx
           )
  end
end
