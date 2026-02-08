defmodule KsefHub.Repo.Migrations.BackfillCompanyId do
  @moduledoc """
  Data migration: for each distinct NIP in ksef_credentials, create a company
  row (if not exists), then backfill company_id on credentials, invoices (by
  matching seller_nip), and checkpoints (by matching nip). Finally enforce
  NOT NULL on company_id columns.
  """
  use Ecto.Migration

  def up do
    # Step 1: Create companies for each distinct NIP in credentials
    execute("""
    INSERT INTO companies (id, name, nip, is_active, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      'Company ' || nip,
      nip,
      true,
      NOW(),
      NOW()
    FROM (SELECT DISTINCT nip FROM ksef_credentials WHERE nip IS NOT NULL) AS creds
    WHERE NOT EXISTS (
      SELECT 1 FROM companies WHERE companies.nip = creds.nip
    )
    """)

    # Step 2: Backfill company_id on credentials (match by NIP)
    execute("""
    UPDATE ksef_credentials
    SET company_id = companies.id
    FROM companies
    WHERE ksef_credentials.nip = companies.nip
      AND ksef_credentials.company_id IS NULL
    """)

    # Step 3: Backfill company_id on invoices (match seller_nip to credential's NIP -> company)
    execute("""
    UPDATE invoices
    SET company_id = companies.id
    FROM companies
    INNER JOIN ksef_credentials ON ksef_credentials.company_id = companies.id
    WHERE invoices.seller_nip = ksef_credentials.nip
      AND invoices.company_id IS NULL
    """)

    # Step 4: Backfill company_id on checkpoints (match by NIP)
    execute("""
    UPDATE sync_checkpoints
    SET company_id = companies.id
    FROM companies
    WHERE sync_checkpoints.nip = companies.nip
      AND sync_checkpoints.company_id IS NULL
    """)

    # Step 5: Enforce NOT NULL on company_id columns
    alter table(:ksef_credentials) do
      modify :company_id, :binary_id, null: false
    end

    alter table(:invoices) do
      modify :company_id, :binary_id, null: false
    end

    alter table(:sync_checkpoints) do
      modify :company_id, :binary_id, null: false
    end
  end

  def down do
    alter table(:ksef_credentials) do
      modify :company_id, :binary_id, null: true
    end

    alter table(:invoices) do
      modify :company_id, :binary_id, null: true
    end

    alter table(:sync_checkpoints) do
      modify :company_id, :binary_id, null: true
    end
  end
end
