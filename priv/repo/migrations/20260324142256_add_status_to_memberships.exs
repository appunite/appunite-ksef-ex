defmodule KsefHub.Repo.Migrations.AddStatusToMemberships do
  use Ecto.Migration

  def change do
    alter table(:memberships) do
      add :status, :string, null: false, default: "active"
    end
  end
end
