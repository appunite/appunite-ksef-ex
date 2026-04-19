defmodule KsefHub.Repo.Migrations.RevertTokenDigestToToken do
  use Ecto.Migration

  def up do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'invoice_public_tokens' AND column_name = 'token_digest'
      ) THEN
        ALTER TABLE invoice_public_tokens RENAME COLUMN token_digest TO token;
      END IF;
    END $$;
    """)
  end

  def down do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'invoice_public_tokens' AND column_name = 'token'
      ) THEN
        ALTER TABLE invoice_public_tokens RENAME COLUMN token TO token_digest;
      END IF;
    END $$;
    """)
  end
end
