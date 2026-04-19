defmodule KsefHub.Repo.Migrations.RenameReviewerViewerRoles do
  use Ecto.Migration

  def up do
    execute("UPDATE memberships SET role = 'approver' WHERE role = 'reviewer'")
    execute("UPDATE memberships SET role = 'analyst' WHERE role = 'viewer'")
    execute("UPDATE invitations SET role = 'approver' WHERE role = 'reviewer'")
  end

  def down do
    execute("UPDATE memberships SET role = 'reviewer' WHERE role = 'approver'")
    execute("UPDATE memberships SET role = 'viewer' WHERE role = 'analyst'")
    execute("UPDATE invitations SET role = 'reviewer' WHERE role = 'approver'")
  end
end
