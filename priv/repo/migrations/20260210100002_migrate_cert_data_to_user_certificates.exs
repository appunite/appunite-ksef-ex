defmodule KsefHub.Repo.Migrations.MigrateCertDataToUserCertificates do
  @moduledoc """
  Data migration: copies certificate data from ksef_credentials to user_certificates.

  For each credential with certificate data, finds the company's owner via memberships
  and creates a user_certificate for that owner (skipping if they already have one).
  """
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO user_certificates (id, user_id, certificate_data_encrypted, certificate_password_encrypted, certificate_subject, not_after, is_active, inserted_at, updated_at)
    SELECT DISTINCT ON (m.user_id)
      gen_random_uuid(),
      m.user_id,
      kc.certificate_data_encrypted,
      kc.certificate_password_encrypted,
      kc.certificate_subject,
      kc.certificate_expires_at,
      true,
      NOW(),
      NOW()
    FROM ksef_credentials kc
    JOIN memberships m ON m.company_id = kc.company_id AND m.role = 'owner'
    WHERE kc.certificate_data_encrypted IS NOT NULL
      AND kc.is_active = true
      AND NOT EXISTS (
        SELECT 1 FROM user_certificates uc
        WHERE uc.user_id = m.user_id AND uc.is_active = true
      )
    ORDER BY m.user_id, kc.updated_at DESC
    """)
  end

  def down do
    execute("DELETE FROM user_certificates")
  end
end
