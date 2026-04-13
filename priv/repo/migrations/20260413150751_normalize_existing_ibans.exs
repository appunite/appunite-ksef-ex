defmodule KsefHub.Repo.Migrations.NormalizeExistingIbans do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE payment_requests
    SET iban = UPPER(REGEXP_REPLACE(TRIM(iban), '[\\s\\-]', '', 'g'))
    WHERE iban ~ '[\\s\\-]'
    """)

    execute("""
    UPDATE company_bank_accounts
    SET iban = UPPER(REGEXP_REPLACE(TRIM(iban), '[\\s\\-]', '', 'g'))
    WHERE iban ~ '[\\s\\-]'
    """)

    execute("""
    UPDATE invoices
    SET iban = UPPER(REGEXP_REPLACE(TRIM(iban), '[\\s\\-]', '', 'g'))
    WHERE iban ~ '[\\s\\-]'
    """)
  end

  def down do
    :ok
  end
end
