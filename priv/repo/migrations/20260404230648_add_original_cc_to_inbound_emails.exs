defmodule KsefHub.Repo.Migrations.AddOriginalCcToInboundEmails do
  use Ecto.Migration

  def change do
    alter table(:inbound_emails) do
      add :original_cc, :text
    end
  end
end
