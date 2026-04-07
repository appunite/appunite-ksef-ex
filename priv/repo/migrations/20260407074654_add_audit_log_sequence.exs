defmodule KsefHub.Repo.Migrations.AddAuditLogSequence do
  use Ecto.Migration

  def change do
    execute(
      "CREATE SEQUENCE audit_logs_seq",
      "DROP SEQUENCE audit_logs_seq"
    )

    alter table(:audit_logs) do
      add :sequence, :bigint, default: fragment("nextval('audit_logs_seq')")
    end

    create index(:audit_logs, [:inserted_at, :sequence])

    drop_if_exists index(:audit_logs, [:inserted_at])
  end
end
