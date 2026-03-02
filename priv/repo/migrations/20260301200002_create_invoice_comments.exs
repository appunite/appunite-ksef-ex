defmodule KsefHub.Repo.Migrations.CreateInvoiceComments do
  use Ecto.Migration

  def change do
    create table(:invoice_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :text, null: false

      add :invoice_id, references(:invoices, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      timestamps()
    end

    create index(:invoice_comments, [:invoice_id, :inserted_at])
  end
end
