defmodule KsefHub.Repo.Migrations.AddCompanyIdToCredentials do
  use Ecto.Migration

  def change do
    alter table(:ksef_credentials) do
      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict)
    end

    # Drop old unique index on nip
    drop_if_exists unique_index(:ksef_credentials, [:nip])

    # New: only one active credential per company
    create unique_index(:ksef_credentials, [:company_id],
             where: "is_active = true",
             name: :ksef_credentials_company_id_active_index
           )

    create index(:ksef_credentials, [:company_id])
  end
end
