defmodule KsefHub.Repo.Migrations.RemoveCertColumnsFromCredentials do
  @moduledoc """
  Removes certificate data columns from ksef_credentials.

  Certificate data now lives in user_certificates (user-scoped).
  The ksef_credentials table keeps only sync config: NIP, tokens, sync state.
  """
  use Ecto.Migration

  def change do
    alter table(:ksef_credentials) do
      remove(:certificate_data_encrypted, :binary, null: true)
      remove(:certificate_password_encrypted, :binary, null: true)
      remove(:certificate_subject, :string, null: true)
      remove(:certificate_expires_at, :date, null: true)
    end
  end
end
