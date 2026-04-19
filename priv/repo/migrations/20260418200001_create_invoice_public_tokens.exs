defmodule KsefHub.Repo.Migrations.CreateInvoicePublicTokens do
  use Ecto.Migration

  def change do
    create table(:invoice_public_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :invoice_id,
          references(:invoices, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :token, :string, size: 44, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:invoice_public_tokens, [:token])
    create index(:invoice_public_tokens, [:invoice_id, :user_id])
  end
end
