defmodule KsefHub.Repo.Migrations.AddInboundEmailSettingsToCompanies do
  use Ecto.Migration

  def change do
    alter table(:companies) do
      add :inbound_allowed_sender_domain, :string
      add :inbound_cc_email, :string
    end
  end
end
