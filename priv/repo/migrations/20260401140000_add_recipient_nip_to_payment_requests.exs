defmodule KsefHub.Repo.Migrations.AddRecipientNipToPaymentRequests do
  use Ecto.Migration

  def change do
    alter table(:payment_requests) do
      add :recipient_nip, :string
    end
  end
end
