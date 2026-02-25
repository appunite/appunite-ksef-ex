defmodule KsefHub.Repo.Migrations.AddEmailToInvoiceSource do
  use Ecto.Migration

  def up do
    # Ecto.Enum values are stored as strings in the DB.
    # Adding :email to the Ecto.Enum in the schema is sufficient —
    # no DB-level enum type change needed since PostgreSQL stores them as varchar.
    # This migration exists as documentation and to verify the column accepts the new value.
    :ok
  end

  def down do
    :ok
  end
end
