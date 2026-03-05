defmodule KsefHub.InvoiceClassifier.WorkerTest do
  use KsefHub.DataCase, async: false

  import KsefHub.Factory
  import Mox

  alias KsefHub.InvoiceClassifier.Worker

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

      assert {:ok, %Oban.Job{}} = Worker.maybe_enqueue(invoice)
    end

    test "skips income invoices", %{company: company} do
      invoice = insert(:invoice, company: company, type: :income)

      assert :skip = Worker.maybe_enqueue(invoice)
    end
  end

  describe "perform/1" do
    test "runs classification for expense invoices", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)

      expect_successful_predictions()

      job = build_job(invoice)
      assert :ok = Worker.perform(job)
    end

    test "cancels when invoice not found", %{company: company} do
      job = %Oban.Job{
        args: %{
          "invoice_id" => Ecto.UUID.generate(),
          "company_id" => company.id
        }
      }

      assert {:cancel, "invoice not found"} = Worker.perform(job)
    end

    test "cancels for income invoices", %{company: company} do
      invoice = insert(:invoice, company: company, type: :income)
      job = build_job(invoice)

      assert {:cancel, "not an expense invoice"} = Worker.perform(job)
    end

    test "cancels for already manually classified invoices", %{company: company} do
      invoice =
        insert(:manual_invoice,
          company: company,
          type: :expense,
          prediction_status: :manual
        )

      job = build_job(invoice)

      assert {:cancel, "already manually classified"} = Worker.perform(job)
    end

    test "cancels when classification service is not configured", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)

      KsefHub.InvoiceClassifier.Mock
      |> expect(:predict_category, fn _input ->
        {:error, :classifier_not_configured}
      end)
      |> expect(:predict_tag, fn _input ->
        {:ok,
         %{
           "top_tag" => "x",
           "top_probability" => 0.0,
           "model_version" => "v1.0",
           "probabilities" => %{}
         }}
      end)

      job = build_job(invoice)
      assert {:cancel, "classification service not configured"} = Worker.perform(job)
    end

    test "returns error for transient failures to allow retry", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)

      KsefHub.InvoiceClassifier.Mock
      |> expect(:predict_category, fn _input ->
        {:error, {:request_failed, :timeout}}
      end)
      |> expect(:predict_tag, fn _input ->
        {:error, {:request_failed, :timeout}}
      end)

      job = build_job(invoice)
      assert {:error, {:request_failed, :timeout}} = Worker.perform(job)
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
    KsefHub.InvoiceClassifier.Mock
    |> expect(:predict_category, fn _input ->
      {:ok,
       %{
         "top_category" => "some:category",
         "top_probability" => 0.50,
         "model_version" => "v1.0",
         "probabilities" => %{}
       }}
    end)
    |> expect(:predict_tag, fn _input ->
      {:ok,
       %{
         "top_tag" => "some-tag",
         "top_probability" => 0.50,
         "model_version" => "v1.0",
         "probabilities" => %{}
       }}
    end)
  end
end
