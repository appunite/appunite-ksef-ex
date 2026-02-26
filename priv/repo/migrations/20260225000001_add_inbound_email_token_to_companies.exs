defmodule KsefHub.Repo.Migrations.AddInboundEmailTokenToCompanies do
  use Ecto.Migration

  def change do
    alter table(:companies) do
      add :inbound_email_token, :string, size: 8
    end

    create unique_index(:companies, [:inbound_email_token],
             where: "inbound_email_token IS NOT NULL",
             name: :companies_inbound_email_token_unique
           )
  end
end
