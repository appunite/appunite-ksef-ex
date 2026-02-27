defmodule KsefHub.Repo.Migrations.AddInboundEmailTokenPlaintextToCompanies do
  use Ecto.Migration

  def change do
    alter table(:companies) do
      add :inbound_email_token, :string, size: 8
    end
  end
end
