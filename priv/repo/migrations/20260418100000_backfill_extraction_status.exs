defmodule KsefHub.Repo.Migrations.BackfillExtractionStatus do
  use Ecto.Migration

  # Intentionally frozen copy of KsefHub.InvoiceExtractor.Placeholders.values/0
  # as they existed when this migration was written. Migrations must be
  # self-contained snapshots — referencing the live module would silently change
  # this migration's behaviour if the placeholder list grows in the future.
  # New placeholders require a separate backfill migration.
  @placeholders ["-", "--", "N/A", "n/a", "null", "`"]

  @doc false
  def up do
    # Some invoices were created before net_amount/seller_nip were added to
    # @critical_extraction_fields in Extraction, so their stored :complete
    # status is stale. Recomputing it here ensures the UI warning banner fires
    # and analytics does not silently treat them as zero-cost.
    #
    # Replicates present_value? logic: NULL, blank, or known LLM placeholder
    # strings count as absent. Numeric/date fields only need the NULL check.
    placeholder_list = Enum.map_join(@placeholders, ", ", &"'#{&1}'")

    absent_string = fn col ->
      "#{col} IS NULL OR TRIM(#{col}) = '' OR TRIM(#{col}) IN (#{placeholder_list})"
    end

    execute """
    UPDATE invoices
    SET extraction_status = 'partial',
        updated_at = NOW()
    WHERE extraction_status = 'complete'
      AND (
        net_amount IS NULL
        OR gross_amount IS NULL
        OR issue_date IS NULL
        OR #{absent_string.("seller_nip")}
        OR #{absent_string.("seller_name")}
        OR #{absent_string.("invoice_number")}
      )
    """
  end

  @doc false
  def down do
    # Not reversible — restoring the original stale :complete statuses
    # would reintroduce the data quality problem this migration fixed.
    :ok
  end
end
