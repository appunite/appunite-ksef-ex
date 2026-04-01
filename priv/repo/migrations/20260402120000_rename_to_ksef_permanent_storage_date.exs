defmodule KsefHub.Repo.Migrations.RenameToKsefPermanentStorageDate do
  use Ecto.Migration

  def change do
    rename table(:invoices), :permanent_storage_date, to: :ksef_permanent_storage_date
  end
end
