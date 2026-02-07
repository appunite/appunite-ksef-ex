defmodule KsefHub.Repo.Migrations.CreateKsefCredentials do
  use Ecto.Migration

  def change do
    create table(:ksef_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :nip, :string, null: false
      add :certificate_data, :binary
      add :certificate_password_encrypted, :binary
      add :certificate_expires_at, :date
      add :certificate_subject, :string
      add :last_sync_at, :utc_datetime_usec
      add :is_active, :boolean, default: true, null: false
      add :refresh_token_encrypted, :binary
      add :refresh_token_expires_at, :utc_datetime_usec
      add :access_token, :binary
      add :access_token_expires_at, :utc_datetime_usec

      timestamps()
    end

    create unique_index(:ksef_credentials, [:nip])
    create index(:ksef_credentials, [:is_active])
  end
end
