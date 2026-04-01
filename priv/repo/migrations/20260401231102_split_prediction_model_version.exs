defmodule KsefHub.Repo.Migrations.SplitPredictionModelVersion do
  use Ecto.Migration

  def change do
    rename table(:invoices), :prediction_model_version, to: :prediction_category_model_version

    alter table(:invoices) do
      add :prediction_tag_model_version, :string
    end

    flush()

    execute "UPDATE invoices SET prediction_tag_model_version = prediction_category_model_version",
            "SELECT 1"
  end
end
