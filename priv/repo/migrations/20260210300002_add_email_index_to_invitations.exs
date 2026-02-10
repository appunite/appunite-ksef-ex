defmodule KsefHub.Repo.Migrations.AddEmailIndexToInvitations do
  use Ecto.Migration

  def change do
    create index(:invitations, [:email])
  end
end
