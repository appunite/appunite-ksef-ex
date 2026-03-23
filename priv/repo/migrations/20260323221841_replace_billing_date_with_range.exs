defmodule KsefHub.Repo.Migrations.ReplaceBillingDateWithRange do
  use Ecto.Migration

  def up do
    alter table(:invoices) do
      add :billing_date_from, :date
      add :billing_date_to, :date
    end

    execute "UPDATE invoices SET billing_date_from = billing_date, billing_date_to = billing_date"

    alter table(:invoices) do
      remove :billing_date
    end

    drop_if_exists index(:invoices, [:company_id, :billing_date])

    create index(:invoices, [:company_id, :billing_date_from, :billing_date_to])
  end

  def down do
    alter table(:invoices) do
      add :billing_date, :date
    end

    execute "UPDATE invoices SET billing_date = billing_date_from"

    drop_if_exists index(:invoices, [:company_id, :billing_date_from, :billing_date_to])

    alter table(:invoices) do
      remove :billing_date_from
      remove :billing_date_to
    end

    create index(:invoices, [:company_id, :billing_date])
  end
end
