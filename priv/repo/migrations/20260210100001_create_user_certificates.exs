defmodule KsefHub.Repo.Migrations.CreateUserCertificates do
  use Ecto.Migration

  def change do
    create table(:user_certificates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :certificate_data_encrypted, :binary, null: false
      add :certificate_password_encrypted, :binary, null: false
      add :certificate_subject, :string
      add :not_before, :date
      add :not_after, :date
      add :fingerprint, :string
      add :is_active, :boolean, default: true, null: false

      timestamps()
    end

    create index(:user_certificates, [:user_id])

    create unique_index(:user_certificates, [:user_id],
             where: "is_active = true",
             name: :user_certificates_user_id_active_index
           )
  end
end
