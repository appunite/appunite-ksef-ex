defmodule KsefHub.Repo.Migrations.CreateFiles do
  use Ecto.Migration

  def change do
    create table(:files, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :content, :binary, null: false
      add :content_type, :string, null: false
      add :filename, :string
      add :byte_size, :integer

      timestamps(updated_at: false)
    end
  end
end
