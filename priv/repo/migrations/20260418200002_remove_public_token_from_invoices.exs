defmodule KsefHub.Repo.Migrations.RemovePublicTokenFromInvoices do
  use Ecto.Migration

  def up do
    drop_if_exists index(:invoices, [:public_token],
                     where: "public_token IS NOT NULL",
                     name: :invoices_public_token_index
                   )

    alter table(:invoices) do
      remove :public_token
    end
  end

  def down do
    alter table(:invoices) do
      add :public_token, :string, size: 44
    end

    create unique_index(:invoices, [:public_token],
             where: "public_token IS NOT NULL",
             name: :invoices_public_token_index
           )
  end
end
