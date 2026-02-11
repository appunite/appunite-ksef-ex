defmodule KsefHub.Repo.Migrations.RenameInvoiceReviewerToReviewer do
  use Ecto.Migration

  def up do
    execute "UPDATE memberships SET role = 'reviewer' WHERE role = 'invoice_reviewer'"
    execute "UPDATE invitations SET role = 'reviewer' WHERE role = 'invoice_reviewer'"
  end

  def down do
    execute "UPDATE memberships SET role = 'invoice_reviewer' WHERE role = 'reviewer'"
    execute "UPDATE invitations SET role = 'invoice_reviewer' WHERE role = 'reviewer'"
  end
end
