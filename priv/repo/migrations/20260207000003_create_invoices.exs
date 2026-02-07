defmodule KsefHub.Repo.Migrations.CreateInvoices do
  use Ecto.Migration

  def change do
    create table(:invoices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ksef_number, :string
      add :type, :string, null: false
      add :xml_content, :text
      add :seller_nip, :string
      add :seller_name, :string
      add :buyer_nip, :string
      add :buyer_name, :string
      add :invoice_number, :string
      add :issue_date, :date
      add :net_amount, :decimal, precision: 15, scale: 2
      add :vat_amount, :decimal, precision: 15, scale: 2
      add :gross_amount, :decimal, precision: 15, scale: 2
      add :currency, :string, default: "PLN"
      add :status, :string, default: "pending", null: false
      add :ksef_acquisition_date, :utc_datetime_usec
      add :permanent_storage_date, :utc_datetime_usec

      timestamps()
    end

    create unique_index(:invoices, [:ksef_number], where: "ksef_number IS NOT NULL")
    create index(:invoices, [:type, :status])
    create index(:invoices, [:seller_nip])
    create index(:invoices, [:buyer_nip])
    create index(:invoices, [:issue_date])
    create index(:invoices, [:permanent_storage_date])
  end
end
