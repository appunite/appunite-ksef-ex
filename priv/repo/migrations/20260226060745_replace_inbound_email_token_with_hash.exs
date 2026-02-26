defmodule KsefHub.Repo.Migrations.ReplaceInboundEmailTokenWithHash do
  use Ecto.Migration

  def change do
    alter table(:companies) do
      add :inbound_email_token_hash, :string, size: 64
      remove :inbound_email_token, :string, size: 8
    end

    drop_if_exists unique_index(:companies, [:inbound_email_token],
                     name: :companies_inbound_email_token_unique
                   )

    create unique_index(:companies, [:inbound_email_token_hash],
             where: "inbound_email_token_hash IS NOT NULL",
             name: :companies_inbound_email_token_hash_unique
           )
  end
end
