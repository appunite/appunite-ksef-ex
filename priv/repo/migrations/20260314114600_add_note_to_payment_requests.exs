defmodule KsefHub.Repo.Migrations.AddNoteToPaymentRequests do
  use Ecto.Migration

  def change do
    alter table(:payment_requests) do
      add :note, :text
    end
  end
end
