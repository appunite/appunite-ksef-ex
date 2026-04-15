defmodule KsefHub.Repo.Migrations.RenameInvoiceKindValues do
  use Ecto.Migration

  @mappings [
    {"VAT", "vat"},
    {"KOR", "correction"},
    {"ZAL", "advance"},
    {"ROZ", "advance_settlement"},
    {"UPR", "simplified"},
    {"KOR_ZAL", "advance_correction"},
    {"KOR_ROZ", "settlement_correction"}
  ]

  def up do
    for {old, new} <- @mappings do
      execute("UPDATE invoices SET invoice_kind = '#{new}' WHERE invoice_kind = '#{old}'")
    end

    alter table(:invoices) do
      modify :invoice_kind, :string, default: "vat", null: false
    end
  end

  def down do
    for {old, new} <- @mappings do
      execute("UPDATE invoices SET invoice_kind = '#{old}' WHERE invoice_kind = '#{new}'")
    end

    alter table(:invoices) do
      modify :invoice_kind, :string, default: "VAT", null: false
    end
  end
end
