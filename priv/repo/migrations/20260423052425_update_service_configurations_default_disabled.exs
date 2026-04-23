defmodule KsefHub.Repo.Migrations.UpdateServiceConfigurationsDefaultDisabled do
  use Ecto.Migration

  def up do
    execute("UPDATE service_configurations SET enabled = false")
  end

  def down do
    execute("UPDATE service_configurations SET enabled = true")
  end
end
