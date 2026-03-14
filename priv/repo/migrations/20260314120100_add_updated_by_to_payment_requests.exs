defmodule KsefHub.Repo.Migrations.AddUpdatedByToPaymentRequests do
  use Ecto.Migration

  def change do
    alter table(:payment_requests) do
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end
  end
end
