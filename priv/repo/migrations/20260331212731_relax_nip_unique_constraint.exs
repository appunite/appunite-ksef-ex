defmodule KsefHub.Repo.Migrations.RelaxNipUniqueConstraint do
  use Ecto.Migration

  def change do
    drop unique_index(:companies, [:nip])
  end
end
