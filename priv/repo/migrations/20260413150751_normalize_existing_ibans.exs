defmodule KsefHub.Repo.Migrations.NormalizeExistingIbans do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE payment_requests
    SET iban = CASE
      WHEN REGEXP_REPLACE(TRIM(iban), '[\\s\\-]', '', 'g') ~ '^[A-Za-z]{2}\\d{2}'
      THEN UPPER(REGEXP_REPLACE(TRIM(iban), '[\\s\\-]', '', 'g'))
      ELSE REGEXP_REPLACE(TRIM(iban), '[\\s\\-]', '', 'g')
    END
    WHERE iban ~ '[\\s\\-]' OR iban ~ '^[a-z]{2}'
    """)

    execute("""
    UPDATE company_bank_accounts
    SET iban = CASE
      WHEN REGEXP_REPLACE(TRIM(iban), '[\\s\\-]', '', 'g') ~ '^[A-Za-z]{2}\\d{2}'
      THEN UPPER(REGEXP_REPLACE(TRIM(iban), '[\\s\\-]', '', 'g'))
      ELSE REGEXP_REPLACE(TRIM(iban), '[\\s\\-]', '', 'g')
    END
    WHERE iban ~ '[\\s\\-]' OR iban ~ '^[a-z]{2}'
    """)

    execute("""
    UPDATE invoices
    SET iban = CASE
      WHEN REGEXP_REPLACE(TRIM(iban), '[\\s\\-]', '', 'g') ~ '^[A-Za-z]{2}\\d{2}'
      THEN UPPER(REGEXP_REPLACE(TRIM(iban), '[\\s\\-]', '', 'g'))
      ELSE REGEXP_REPLACE(TRIM(iban), '[\\s\\-]', '', 'g')
    END
    WHERE iban ~ '[\\s\\-]' OR iban ~ '^[a-z]{2}'
    """)
  end

  def down do
    :ok
  end
end
