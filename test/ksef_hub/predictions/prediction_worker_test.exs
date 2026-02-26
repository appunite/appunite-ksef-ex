defmodule KsefHub.Predictions.PredictionWorkerTest do
  use KsefHub.DataCase, async: false

  import KsefHub.Factory
  import Mox

  alias KsefHub.Predictions.PredictionWorker

  @moduletag :set_mox_global

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    company = insert(:company)
    %{company: company}
  end

  describe "maybe_enqueue/1" do
    test "enqueues job for expense invoices", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)

      # Oban inline mode will execute the job immediately, so we need mock expectations
      expect_successful_predictions()

      assert {:ok, %Oban.Job{}} = PredictionWorker.maybe_enqueue(invoice)
    end

    test "skips income invoices", %{company: company} do
      invoice = insert(:invoice, company: company, type: :income)

      assert :skip = PredictionWorker.maybe_enqueue(invoice)
    end
  end

  describe "perform/1" do
    test "runs prediction for expense invoices", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)

      expect_successful_predictions()

      job = build_job(invoice)
      assert :ok = PredictionWorker.perform(job)
    end

    test "cancels when invoice not found", %{company: company} do
      job = %Oban.Job{
        args: %{
          "invoice_id" => Ecto.UUID.generate(),
          "company_id" => company.id
        }
      }

      assert {:cancel, "invoice not found"} = PredictionWorker.perform(job)
    end

    test "cancels for income invoices", %{company: company} do
      invoice = insert(:invoice, company: company, type: :income)
      job = build_job(invoice)

      assert {:cancel, "not an expense invoice"} = PredictionWorker.perform(job)
    end

    test "cancels for already manually classified invoices", %{company: company} do
      invoice =
        insert(:manual_invoice,
          company: company,
          type: :expense,
          prediction_status: :manual
        )

      job = build_job(invoice)

      assert {:cancel, "already manually classified"} = PredictionWorker.perform(job)
    end

    test "cancels when prediction service is not configured", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)

      KsefHub.Predictions.Mock
      |> expect(:predict_category, fn _input ->
        {:error, :prediction_service_not_configured}
      end)
      |> expect(:predict_tag, fn _input ->
        {:ok, %{"predicted_label" => "x", "confidence" => 0.0, "model_version" => "v1.0", "probabilities" => %{}}}
      end)

      job = build_job(invoice)
      assert {:cancel, "prediction service not configured"} = PredictionWorker.perform(job)
    end

    test "returns error for transient failures to allow retry", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)

      KsefHub.Predictions.Mock
      |> expect(:predict_category, fn _input ->
        {:error, {:request_failed, :timeout}}
      end)
      |> expect(:predict_tag, fn _input ->
        {:error, {:request_failed, :timeout}}
      end)

      job = build_job(invoice)
      assert {:error, {:request_failed, :timeout}} = PredictionWorker.perform(job)
    end
  end

  @spec build_job(KsefHub.Invoices.Invoice.t()) :: Oban.Job.t()
  defp build_job(invoice) do
    %Oban.Job{
      args: %{
        "invoice_id" => invoice.id,
        "company_id" => invoice.company_id
      }
    }
  end

  @spec expect_successful_predictions() :: :ok
  defp expect_successful_predictions do
    KsefHub.Predictions.Mock
    |> expect(:predict_category, fn _input ->
      {:ok,
       %{
         "predicted_label" => "some:category",
         "confidence" => 0.50,
         "model_version" => "v1.0",
         "probabilities" => %{}
       }}
    end)
    |> expect(:predict_tag, fn _input ->
      {:ok,
       %{
         "predicted_label" => "some-tag",
         "confidence" => 0.50,
         "model_version" => "v1.0",
         "probabilities" => %{}
       }}
    end)
  end
end
