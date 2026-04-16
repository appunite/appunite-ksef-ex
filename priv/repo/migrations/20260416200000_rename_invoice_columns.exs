defmodule KsefHub.Repo.Migrations.RenameInvoiceColumns do
  use Ecto.Migration

  def up do
    rename table(:invoices), :status, to: :expense_approval_status
    rename table(:invoices), :category_id, to: :expense_category_id
    rename table(:invoices), :cost_line, to: :expense_cost_line
    rename table(:invoices), :prediction_category_name, to: :prediction_expense_category_name

    rename table(:invoices), :prediction_category_confidence,
      to: :prediction_expense_category_confidence

    rename table(:invoices), :prediction_category_model_version,
      to: :prediction_expense_category_model_version

    rename table(:invoices), :prediction_category_probabilities,
      to: :prediction_expense_category_probabilities

    rename table(:invoices), :prediction_tag_name, to: :prediction_expense_tag_name
    rename table(:invoices), :prediction_tag_confidence, to: :prediction_expense_tag_confidence

    rename table(:invoices), :prediction_tag_model_version,
      to: :prediction_expense_tag_model_version

    rename table(:invoices), :prediction_tag_probabilities,
      to: :prediction_expense_tag_probabilities
  end

  def down do
    rename table(:invoices), :expense_approval_status, to: :status
    rename table(:invoices), :expense_category_id, to: :category_id
    rename table(:invoices), :expense_cost_line, to: :cost_line
    rename table(:invoices), :prediction_expense_category_name, to: :prediction_category_name

    rename table(:invoices), :prediction_expense_category_confidence,
      to: :prediction_category_confidence

    rename table(:invoices), :prediction_expense_category_model_version,
      to: :prediction_category_model_version

    rename table(:invoices), :prediction_expense_category_probabilities,
      to: :prediction_category_probabilities

    rename table(:invoices), :prediction_expense_tag_name, to: :prediction_tag_name
    rename table(:invoices), :prediction_expense_tag_confidence, to: :prediction_tag_confidence

    rename table(:invoices), :prediction_expense_tag_model_version,
      to: :prediction_tag_model_version

    rename table(:invoices), :prediction_expense_tag_probabilities,
      to: :prediction_tag_probabilities
  end
end
