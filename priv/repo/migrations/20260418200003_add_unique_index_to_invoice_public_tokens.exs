defmodule KsefHub.Repo.Migrations.AddUniqueIndexToInvoicePublicTokens do
  use Ecto.Migration

  def up do
    drop_if_exists index(:invoice_public_tokens, [:invoice_id, :user_id])
    create unique_index(:invoice_public_tokens, [:invoice_id, :user_id])
  end

  def down do
    drop_if_exists unique_index(:invoice_public_tokens, [:invoice_id, :user_id])
    create index(:invoice_public_tokens, [:invoice_id, :user_id])
  end
end
