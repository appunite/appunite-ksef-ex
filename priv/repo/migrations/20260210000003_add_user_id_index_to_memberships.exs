defmodule KsefHub.Repo.Migrations.AddUserIdIndexToMemberships do
  use Ecto.Migration

  def change do
    create index(:memberships, [:user_id])
  end
end
