defmodule KsefHub.Repo.Migrations.AddRecipientNipToPaymentRequests do
  @moduledoc "Adds recipient_nip column to payment_requests for NIP-based payment details in CSV exports."

  use Ecto.Migration

  @doc "Adds nullable recipient_nip string column to payment_requests."
  @spec change() :: term()
  def change do
    alter table(:payment_requests) do
      add :recipient_nip, :string
    end
  end
end
