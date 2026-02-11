defmodule KsefHub.Repo.Migrations.CreateInvitations do
  use Ecto.Migration

  def change do
    create table(:invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :text, null: false
      add :role, :text, null: false
      add :token_hash, :text, null: false
      add :status, :text, null: false, default: "pending"
      add :expires_at, :utc_datetime, null: false

      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict), null: false

      add :invited_by_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      timestamps()
    end

    create index(:invitations, [:company_id])
    create index(:invitations, [:invited_by_id])
    create index(:invitations, [:token_hash], unique: true)

    create unique_index(:invitations, [:company_id, :email],
             where: "status = 'pending'",
             name: :invitations_company_id_email_pending_index
           )
  end
end
