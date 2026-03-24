defmodule KsefHub.Repo.Migrations.RestrictIncomeInvoices do
  use Ecto.Migration

  def up do
    execute "UPDATE invoices SET access_restricted = true WHERE type = 'income'"
  end

  def down do
    execute "UPDATE invoices SET access_restricted = false WHERE type = 'income'"
  end
end
