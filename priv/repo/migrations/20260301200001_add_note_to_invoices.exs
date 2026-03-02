defmodule KsefHub.Repo.Migrations.AddNoteToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :note, :text
    end
  end
end
