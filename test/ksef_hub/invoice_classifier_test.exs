defmodule KsefHub.InvoiceClassifierTest do
  use KsefHub.DataCase, async: false

  import KsefHub.Factory
  import Mox

  alias KsefHub.InvoiceClassifier
  alias KsefHub.Invoices

  @moduletag :set_mox_global

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    company = insert(:company)
    %{company: company}
  end

  describe "predict_and_apply/1" do
    test "auto-applies category and tag when confidence >= 80% and matches exist", %{
      company: company
    } do
      {:ok, category} = Invoices.create_category(company.id, %{name: "finance:invoices"})
      {:ok, tag} = Invoices.create_tag(company.id, %{name: "monthly"})

      invoice =
        insert(:manual_invoice,
          company: company,
          type: :expense
        )

      expect_predictions(
        category: %{
          "predicted_label" => "finance:invoices",
          "confidence" => 0.92,
          "model_version" => "v1.0",
          "probabilities" => %{"finance:invoices" => 0.92, "hr:payroll" => 0.08}
        },
        tag: %{
          "predicted_label" => "monthly",
          "confidence" => 0.85,
          "model_version" => "v1.0",
          "probabilities" => %{"monthly" => 0.85, "quarterly" => 0.15}
        }
      )

      assert {:ok, updated} = InvoiceClassifier.predict_and_apply(invoice)

      assert updated.prediction_status == :predicted
      assert updated.prediction_category_name == "finance:invoices"
      assert updated.prediction_tag_name == "monthly"
      assert updated.prediction_category_confidence == 0.92
      assert updated.prediction_tag_confidence == 0.85
      assert updated.prediction_model_version == "v1.0"
      assert updated.prediction_predicted_at != nil

      # Verify category was actually applied
      updated = Invoices.get_invoice_with_details!(company.id, updated.id)
      assert updated.category_id == category.id
      assert Enum.any?(updated.tags, &(&1.id == tag.id))
    end

    test "stores predictions as needs_review when confidence < 80%", %{company: company} do
      {:ok, _category} = Invoices.create_category(company.id, %{name: "finance:invoices"})

      invoice = insert(:manual_invoice, company: company, type: :expense)

      expect_predictions(
        category: %{
          "predicted_label" => "finance:invoices",
          "confidence" => 0.65,
          "model_version" => "v1.0",
          "probabilities" => %{"finance:invoices" => 0.65}
        },
        tag: %{
          "predicted_label" => "monthly",
          "confidence" => 0.45,
          "model_version" => "v1.0",
          "probabilities" => %{"monthly" => 0.45}
        }
      )

      assert {:ok, updated} = InvoiceClassifier.predict_and_apply(invoice)

      assert updated.prediction_status == :needs_review
      assert updated.prediction_category_name == "finance:invoices"
      assert updated.prediction_category_confidence == 0.65

      # Category should NOT be applied
      assert updated.category_id == nil
    end

    test "skips non-expense invoices", %{company: company} do
      invoice = insert(:invoice, company: company, type: :income)

      assert {:skip, :not_expense} = InvoiceClassifier.predict_and_apply(invoice)
    end

    test "sets needs_review when high confidence but no matching company category", %{
      company: company
    } do
      # No categories or tags created for this company
      invoice = insert(:manual_invoice, company: company, type: :expense)

      expect_predictions(
        category: %{
          "predicted_label" => "nonexistent:category",
          "confidence" => 0.95,
          "model_version" => "v1.0",
          "probabilities" => %{"nonexistent:category" => 0.95}
        },
        tag: %{
          "predicted_label" => "nonexistent-tag",
          "confidence" => 0.90,
          "model_version" => "v1.0",
          "probabilities" => %{"nonexistent-tag" => 0.90}
        }
      )

      assert {:ok, updated} = InvoiceClassifier.predict_and_apply(invoice)

      # High confidence but no match -> needs_review
      assert updated.prediction_status == :needs_review
      assert updated.category_id == nil
    end

    test "handles classification service errors gracefully", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)

      KsefHub.InvoiceClassifier.Mock
      |> expect(:predict_category, fn _input ->
        {:error, {:classifier_error, 500}}
      end)
      |> expect(:predict_tag, fn _input ->
        {:ok,
         %{
           "predicted_label" => "x",
           "confidence" => 0.0,
           "model_version" => "v1.0",
           "probabilities" => %{}
         }}
      end)

      assert {:error, {:classifier_error, 500}} =
               InvoiceClassifier.predict_and_apply(invoice)
    end

    test "sets predicted when only tag matches above threshold", %{company: company} do
      {:ok, tag} = Invoices.create_tag(company.id, %{name: "monthly"})

      invoice = insert(:manual_invoice, company: company, type: :expense)

      expect_predictions(
        category: %{
          "predicted_label" => "finance:invoices",
          "confidence" => 0.40,
          "model_version" => "v1.0",
          "probabilities" => %{"finance:invoices" => 0.40}
        },
        tag: %{
          "predicted_label" => "monthly",
          "confidence" => 0.90,
          "model_version" => "v1.0",
          "probabilities" => %{"monthly" => 0.90}
        }
      )

      assert {:ok, updated} = InvoiceClassifier.predict_and_apply(invoice)

      assert updated.prediction_status == :predicted
      updated = Invoices.get_invoice_with_details!(company.id, updated.id)
      assert updated.category_id == nil
      assert Enum.any?(updated.tags, &(&1.id == tag.id))
    end

    test "sets predicted when only category matches above threshold", %{company: company} do
      {:ok, category} = Invoices.create_category(company.id, %{name: "finance:invoices"})

      invoice = insert(:manual_invoice, company: company, type: :expense)

      expect_predictions(
        category: %{
          "predicted_label" => "finance:invoices",
          "confidence" => 0.90,
          "model_version" => "v1.0",
          "probabilities" => %{"finance:invoices" => 0.90}
        },
        tag: %{
          "predicted_label" => "some-tag",
          "confidence" => 0.50,
          "model_version" => "v1.0",
          "probabilities" => %{"some-tag" => 0.50}
        }
      )

      assert {:ok, updated} = InvoiceClassifier.predict_and_apply(invoice)

      assert updated.prediction_status == :predicted
      updated = Invoices.get_invoice_with_details!(company.id, updated.id)
      assert updated.category_id == category.id
    end

    test "returns error when category succeeds but tag prediction fails", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)

      KsefHub.InvoiceClassifier.Mock
      |> expect(:predict_category, fn _input ->
        {:ok,
         %{
           "predicted_label" => "finance:invoices",
           "confidence" => 0.90,
           "model_version" => "v1.0",
           "probabilities" => %{}
         }}
      end)
      |> expect(:predict_tag, fn _input ->
        {:error, {:request_failed, :timeout}}
      end)

      assert {:error, {:request_failed, :timeout}} = InvoiceClassifier.predict_and_apply(invoice)

      # Invoice should be unchanged since tag call failed before apply
      reloaded = Invoices.get_invoice!(company.id, invoice.id)
      assert reloaded.prediction_status == nil
    end

    test "auto-applies at exact 80% confidence boundary", %{company: company} do
      {:ok, category} = Invoices.create_category(company.id, %{name: "finance:invoices"})

      invoice = insert(:manual_invoice, company: company, type: :expense)

      expect_predictions(
        category: %{
          "predicted_label" => "finance:invoices",
          "confidence" => 0.80,
          "model_version" => "v1.0",
          "probabilities" => %{"finance:invoices" => 0.80}
        },
        tag: %{
          "predicted_label" => "some-tag",
          "confidence" => 0.79,
          "model_version" => "v1.0",
          "probabilities" => %{"some-tag" => 0.79}
        }
      )

      assert {:ok, updated} = InvoiceClassifier.predict_and_apply(invoice)

      # 0.80 is >= threshold -> predicted; 0.79 is < threshold -> not applied
      assert updated.prediction_status == :predicted
      updated = Invoices.get_invoice_with_details!(company.id, updated.id)
      assert updated.category_id == category.id
    end

    test "stores full probability distributions", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)

      cat_probs = %{"finance:invoices" => 0.60, "hr:payroll" => 0.30, "other:misc" => 0.10}
      tag_probs = %{"monthly" => 0.55, "quarterly" => 0.45}

      expect_predictions(
        category: %{
          "predicted_label" => "finance:invoices",
          "confidence" => 0.60,
          "model_version" => "v2.1",
          "probabilities" => cat_probs
        },
        tag: %{
          "predicted_label" => "monthly",
          "confidence" => 0.55,
          "model_version" => "v2.1",
          "probabilities" => tag_probs
        }
      )

      assert {:ok, updated} = InvoiceClassifier.predict_and_apply(invoice)

      assert updated.prediction_category_probabilities == cat_probs
      assert updated.prediction_tag_probabilities == tag_probs
      assert updated.prediction_model_version == "v2.1"
    end
  end

  describe "mark_prediction_manual/1" do
    test "transitions prediction_status to manual", %{company: company} do
      invoice =
        insert(:manual_invoice,
          company: company,
          type: :expense,
          prediction_status: :predicted
        )

      assert {:ok, updated} = Invoices.mark_prediction_manual(invoice)
      assert updated.prediction_status == :manual
    end

    test "works when prediction_status is nil", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)
      assert invoice.prediction_status == nil

      assert {:ok, updated} = Invoices.mark_prediction_manual(invoice)
      assert updated.prediction_status == :manual
    end

    test "works when prediction_status is needs_review", %{company: company} do
      invoice =
        insert(:manual_invoice,
          company: company,
          type: :expense,
          prediction_status: :needs_review
        )

      assert {:ok, updated} = Invoices.mark_prediction_manual(invoice)
      assert updated.prediction_status == :manual
    end
  end

  @spec expect_predictions(keyword()) :: :ok
  defp expect_predictions(opts) do
    cat_result = Keyword.fetch!(opts, :category)
    tag_result = Keyword.fetch!(opts, :tag)

    KsefHub.InvoiceClassifier.Mock
    |> expect(:predict_category, fn _input -> {:ok, cat_result} end)
    |> expect(:predict_tag, fn _input -> {:ok, tag_result} end)
  end
end
