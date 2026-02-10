defmodule KsefHub.Repo.Migrations.SeedOwnerMemberships do
  @moduledoc """
  Data migration: creates owner memberships for all existing users on all existing companies.

  In the pre-RBAC model, all authenticated users had access to all companies.
  This migration preserves that access by granting owner role to every existing
  user-company pair, so no one loses access after the RBAC transition.
  """
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO memberships (id, user_id, company_id, role, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      u.id,
      c.id,
      'owner',
      NOW(),
      NOW()
    FROM users u
    CROSS JOIN companies c
    ON CONFLICT DO NOTHING
    """)
  end

  def down do
    execute("DELETE FROM memberships")
  end
end
