defmodule KsefHub.Repo.Migrations.CreatePaymentRequests do
  use Ecto.Migration

  def change do
    create table(:payment_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :recipient_name, :string, null: false
      add :recipient_address, :map
      add :amount, :decimal, precision: 15, scale: 2, null: false
      add :currency, :string, null: false, default: "PLN"
      add :title, :string, null: false
      add :iban, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :invoice_id, references(:invoices, type: :binary_id, on_delete: :nilify_all)
      add :company_id, references(:companies, type: :binary_id, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false

      timestamps()
    end

    create index(:payment_requests, [:company_id, :status])
    create index(:payment_requests, [:company_id, :inserted_at])
    create index(:payment_requests, [:invoice_id])
  end
end
