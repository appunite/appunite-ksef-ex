defmodule KsefHub.Repo.Migrations.AddVoidedStatusToPaymentRequests do
  use Ecto.Migration

  def change do
    alter table(:payment_requests) do
      add :voided_at, :utc_datetime_usec
    end
  end
end
