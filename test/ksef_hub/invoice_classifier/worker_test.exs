defmodule KsefHub.InvoiceClassifier.WorkerTest do
  use KsefHub.DataCase, async: false

  import KsefHub.Factory
  import Mox
  import Swoosh.TestAssertions

  alias KsefHub.InvoiceClassifier.Worker

  @moduletag :set_mox_global

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    company = insert(:company)
    insert(:classifier_config, company: company)
    %{company: company}
  end

  describe "maybe_enqueue/2" do
    test "enqueues job for expense invoices", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)

      # Oban inline mode will execute the job immediately, so we need mock expectations
      expect_successful_predictions()

      assert {:ok, %Oban.Job{}} = Worker.maybe_enqueue(invoice)
    end

    test "enqueues job with on_complete args", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)
      expect_successful_predictions()

      on_complete = %{
        worker: "KsefHub.InboundEmail.EmailReplyWorker",
        args: %{
          inbound_email_id: Ecto.UUID.generate(),
          company_id: company.id,
          invoice_id: invoice.id,
          reply_type: "success"
        }
      }

      # In inline mode, the chained EmailReplyWorker will also execute (and cancel
      # because inbound_email_id doesn't exist), but the classifier succeeds.
      assert {:ok, %Oban.Job{}} = Worker.maybe_enqueue(invoice, on_complete: on_complete)
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

    test "cancels when classification is not enabled for company" do
      company_without_config = insert(:company)
      invoice = insert(:manual_invoice, company: company_without_config, type: :expense)

      job = build_job(invoice)
      assert {:cancel, "classification not enabled for this company"} = Worker.perform(job)
    end

    test "cancels when classifier config is disabled" do
      disabled_company = insert(:company)
      insert(:classifier_config, company: disabled_company, enabled: false)
      invoice = insert(:manual_invoice, company: disabled_company, type: :expense)

      job = build_job(invoice)
      assert {:cancel, "classification not enabled for this company"} = Worker.perform(job)
    end

    test "returns error for transient failures to allow retry", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)

      KsefHub.InvoiceClassifier.Mock
      |> expect(:predict_category, fn _input, _config ->
        {:error, {:request_failed, :timeout}}
      end)
      |> expect(:predict_tag, fn _input, _config ->
        {:error, {:request_failed, :timeout}}
      end)

      job = build_job(invoice)
      assert {:error, {:request_failed, :timeout}} = Worker.perform(job)
    end

    test "enqueues on_complete worker after successful classification", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)
      expect_successful_predictions()

      on_complete = %{
        "worker" => "KsefHub.InboundEmail.EmailReplyWorker",
        "args" => %{
          "inbound_email_id" => Ecto.UUID.generate(),
          "company_id" => company.id,
          "invoice_id" => invoice.id,
          "reply_type" => "success"
        }
      }

      job = %Oban.Job{
        args: %{
          "invoice_id" => invoice.id,
          "company_id" => invoice.company_id,
          "on_complete" => on_complete
        }
      }

      # In inline mode, the on_complete job will also execute.
      # The EmailReplyWorker will cancel because the inbound_email_id doesn't exist,
      # but the classifier itself should succeed.
      assert :ok = Worker.perform(job)
    end

    test "enqueues on_complete worker on cancel (non-retryable)", %{company: company} do
      invoice = insert(:invoice, company: company, type: :income)

      on_complete = %{
        "worker" => "KsefHub.InboundEmail.EmailReplyWorker",
        "args" => %{
          "inbound_email_id" => Ecto.UUID.generate(),
          "company_id" => company.id,
          "invoice_id" => invoice.id,
          "reply_type" => "success"
        }
      }

      job = %Oban.Job{
        args: %{
          "invoice_id" => invoice.id,
          "company_id" => invoice.company_id,
          "on_complete" => on_complete
        }
      }

      # Cancelled because income, but on_complete should still fire
      assert {:cancel, "not an expense invoice"} = Worker.perform(job)
    end

    test "does NOT enqueue on_complete on transient error", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)

      KsefHub.InvoiceClassifier.Mock
      |> expect(:predict_category, fn _input, _config ->
        {:error, {:request_failed, :timeout}}
      end)
      |> expect(:predict_tag, fn _input, _config ->
        {:error, {:request_failed, :timeout}}
      end)

      on_complete = %{
        "worker" => "KsefHub.InboundEmail.EmailReplyWorker",
        "args" => %{
          "inbound_email_id" => Ecto.UUID.generate(),
          "company_id" => company.id,
          "invoice_id" => invoice.id,
          "reply_type" => "success"
        }
      }

      job = %Oban.Job{
        args: %{
          "invoice_id" => invoice.id,
          "company_id" => invoice.company_id,
          "on_complete" => on_complete
        }
      }

      assert {:error, {:request_failed, :timeout}} = Worker.perform(job)
      # No email should be sent since the error is transient
      refute_email_sent()
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
    |> expect(:predict_category, fn _input, _config ->
      {:ok,
       %{
         "predicted_label" => "some:category",
         "confidence" => 0.50,
         "model_version" => "v1.0",
         "probabilities" => %{}
       }}
    end)
    |> expect(:predict_tag, fn _input, _config ->
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
