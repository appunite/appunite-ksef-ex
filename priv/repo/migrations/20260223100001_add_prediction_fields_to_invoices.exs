defmodule KsefHub.Repo.Migrations.AddPredictionFieldsToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :prediction_status, :string
      add :prediction_category_name, :string
      add :prediction_tag_name, :string
      add :prediction_category_confidence, :float
      add :prediction_tag_confidence, :float
      add :prediction_model_version, :string
      add :prediction_category_probabilities, :map
      add :prediction_tag_probabilities, :map
      add :prediction_predicted_at, :utc_datetime_usec
    end

    create index(:invoices, [:prediction_status])
  end
end
