defmodule KsefHub.Repo.Migrations.AddExpiresAtToApiTokens do
  use Ecto.Migration

  def change do
    alter table(:api_tokens) do
      add :expires_at, :utc_datetime_usec
    end
  end
end
