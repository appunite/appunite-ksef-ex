defmodule KsefHub.Repo.Migrations.AddPaidAtToPaymentRequests do
  use Ecto.Migration

  def change do
    alter table(:payment_requests) do
      add :paid_at, :utc_datetime_usec
    end
  end
end
