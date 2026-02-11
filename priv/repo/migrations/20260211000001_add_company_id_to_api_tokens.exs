defmodule KsefHub.Repo.Migrations.AddCompanyIdToApiTokens do
  use Ecto.Migration

  def up do
    alter table(:api_tokens) do
      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict)
    end

    create index(:api_tokens, [:company_id])

    # Data migration: associate existing tokens with their creator's earliest owner
    # membership company. Uses a deterministic subquery (ORDER BY + LIMIT 1) so
    # users who own multiple companies get a consistent, single result per token.
    # Tokens without a valid owner membership are deactivated below.
    execute """
    UPDATE api_tokens
    SET company_id = (
      SELECT m.company_id
      FROM memberships m
      WHERE m.user_id = api_tokens.created_by_id
        AND m.role = 'owner'
      ORDER BY m.inserted_at, m.id
      LIMIT 1
    )
    WHERE api_tokens.company_id IS NULL
    """

    execute """
    UPDATE api_tokens
    SET is_active = false
    WHERE company_id IS NULL
      AND is_active = true
    """
  end

  def down do
    raise Ecto.MigrationError,
      message: """
      Cannot reverse: data migration deactivated tokens without owner memberships.
      Rolling back would leave those tokens inactive with no way to restore them.
      """
  end
end
