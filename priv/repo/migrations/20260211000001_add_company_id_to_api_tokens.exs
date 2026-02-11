defmodule KsefHub.Repo.Migrations.AddCompanyIdToApiTokens do
  use Ecto.Migration

  def up do
    alter table(:api_tokens) do
      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict)
    end

    create index(:api_tokens, [:company_id])

    # Data migration: associate existing tokens with their creator's first company
    # (via the creator's owner membership). Tokens without a valid owner membership
    # are deactivated rather than left with NULL company_id.
    execute """
    UPDATE api_tokens
    SET company_id = m.company_id
    FROM memberships m
    WHERE api_tokens.created_by_id = m.user_id
      AND m.role = 'owner'
      AND api_tokens.company_id IS NULL
    """

    execute """
    UPDATE api_tokens
    SET is_active = false
    WHERE company_id IS NULL
      AND is_active = true
    """
  end

  def down do
    drop index(:api_tokens, [:company_id])

    alter table(:api_tokens) do
      remove :company_id, references(:companies, type: :binary_id), null: true
    end
  end
end
