defmodule KsefHub.Repo.Migrations.RenameToKsefPermanentStorageDate do
  use Ecto.Migration

  def change do
    rename table(:invoices), :permanent_storage_date, to: :ksef_permanent_storage_date

    execute(
      "ALTER INDEX invoices_permanent_storage_date_index RENAME TO invoices_ksef_permanent_storage_date_index",
      "ALTER INDEX invoices_ksef_permanent_storage_date_index RENAME TO invoices_permanent_storage_date_index"
    )
  end
end
