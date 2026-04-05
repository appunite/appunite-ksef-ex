defmodule KsefHub.Repo.Migrations.ExtendAuditLogsForActivity do
  use Ecto.Migration

  def change do
    alter table(:audit_logs) do
      add :company_id, references(:companies, type: :binary_id, on_delete: :delete_all)
      add :actor_type, :string, default: "user"
      add :actor_label, :string
    end

    # Composite index for invoice timeline queries
    create index(:audit_logs, [:company_id, :resource_type, :resource_id, :inserted_at])

    # Composite index for platform activity log queries
    create index(:audit_logs, [:company_id, :inserted_at])
  end
end
