defmodule KsefHub.InvoiceClassifierTest do
  use KsefHub.DataCase, async: false

  import KsefHub.Factory
  import Mox

  alias KsefHub.InvoiceClassifier
  alias KsefHub.Invoices

  @moduletag :set_mox_global

  setup :set_mox_from_context
  setup :verify_on_exit!

  @category_threshold 0.71
  @tag_threshold 0.95

  setup do
    prev_cat = Application.get_env(:ksef_hub, :category_confidence_threshold)
    prev_tag = Application.get_env(:ksef_hub, :tag_confidence_threshold)
    Application.put_env(:ksef_hub, :category_confidence_threshold, @category_threshold)
    Application.put_env(:ksef_hub, :tag_confidence_threshold, @tag_threshold)

    on_exit(fn ->
      Application.put_env(:ksef_hub, :category_confidence_threshold, prev_cat)
      Application.put_env(:ksef_hub, :tag_confidence_threshold, prev_tag)
    end)

    company = insert(:company)
    %{company: company}
  end

  describe "predict_and_apply/1" do
    test "auto-applies category and tag when confidence meets both thresholds", %{
      company: company
    } do
      {:ok, category} = Invoices.create_category(company.id, %{identifier: "finance:invoices"})

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
          "confidence" => 0.95,
          "model_version" => "v1.0",
          "probabilities" => %{"monthly" => 0.95, "quarterly" => 0.05}
        }
      )

      assert {:ok, updated} = InvoiceClassifier.predict_and_apply(invoice)

      assert updated.prediction_status == :predicted
      assert updated.prediction_category_name == "finance:invoices"
      assert updated.prediction_tag_name == "monthly"
      assert updated.prediction_category_confidence == 0.92
      assert updated.prediction_tag_confidence == 0.95
      assert updated.prediction_category_model_version == "v1.0"
      assert updated.prediction_tag_model_version == "v1.0"
      assert updated.prediction_predicted_at != nil

      # Verify category and tag were actually applied
      updated = Invoices.get_invoice_with_details!(company.id, updated.id)
      assert updated.category_id == category.id
      assert "monthly" in updated.tags
    end

    test "applies multiple tags when several exceed threshold in probabilities", %{
      company: company
    } do
      invoice = insert(:manual_invoice, company: company, type: :expense)

      expect_predictions(
        category: %{
          "predicted_label" => "nonexistent:cat",
          "confidence" => 0.30,
          "model_version" => "v1.0",
          "probabilities" => %{"nonexistent:cat" => 0.30}
        },
        tag: %{
          "predicted_label" => "monthly",
          "confidence" => 0.97,
          "model_version" => "v1.0",
          "probabilities" => %{"monthly" => 0.97, "recurring" => 0.96, "one-off" => 0.50}
        }
      )

      assert {:ok, updated} = InvoiceClassifier.predict_and_apply(invoice)

      assert updated.prediction_status == :predicted
      updated = Invoices.get_invoice_with_details!(company.id, updated.id)
      assert "monthly" in updated.tags
      assert "recurring" in updated.tags
      refute "one-off" in updated.tags
    end

    test "stores predictions as needs_review when confidence below both thresholds",
         %{company: company} do
      {:ok, _category} = Invoices.create_category(company.id, %{identifier: "finance:invoices"})

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
          "confidence" => 0.45,
          "model_version" => "v1.0",
          "probabilities" => %{"monthly" => 0.45}
        }
      )

      assert {:ok, updated} = InvoiceClassifier.predict_and_apply(invoice)

      assert updated.prediction_status == :needs_review
      assert updated.prediction_category_name == "finance:invoices"
      assert updated.prediction_category_confidence == 0.40

      # Category is NOT applied when confidence is below threshold
      updated = Invoices.get_invoice_with_details!(company.id, updated.id)
      assert updated.category_id == nil
    end

    test "below-threshold tag confidence does not apply tag", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)

      expect_predictions(
        category: %{
          "predicted_label" => "nonexistent:cat",
          "confidence" => 0.30,
          "model_version" => "v1.0",
          "probabilities" => %{"nonexistent:cat" => 0.30}
        },
        tag: %{
          "predicted_label" => "monthly",
          "confidence" => 0.40,
          "model_version" => "v1.0",
          "probabilities" => %{"monthly" => 0.40}
        }
      )

      assert {:ok, updated} = InvoiceClassifier.predict_and_apply(invoice)

      assert updated.prediction_status == :needs_review

      # Tag is NOT applied when confidence is below threshold
      updated = Invoices.get_invoice_with_details!(company.id, updated.id)
      assert updated.tags == []
    end

    test "skips non-expense invoices", %{company: company} do
      invoice = insert(:invoice, company: company, type: :income)

      assert {:skip, :not_expense} = InvoiceClassifier.predict_and_apply(invoice)
    end

    test "applies tag but not category when category has no match", %{
      company: company
    } do
      # No categories created for this company, but tags are strings so they always apply
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
          "confidence" => 0.96,
          "model_version" => "v1.0",
          "probabilities" => %{"nonexistent-tag" => 0.96}
        }
      )

      assert {:ok, updated} = InvoiceClassifier.predict_and_apply(invoice)

      # Tag applied (string, no matching needed), but category has no match -> predicted
      assert updated.prediction_status == :predicted
      updated = Invoices.get_invoice_with_details!(company.id, updated.id)
      assert updated.category_id == nil
      assert "nonexistent-tag" in updated.tags
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

    test "sets predicted when only tag is above tag threshold", %{company: company} do
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
          "confidence" => 0.96,
          "model_version" => "v1.0",
          "probabilities" => %{"monthly" => 0.96}
        }
      )

      assert {:ok, updated} = InvoiceClassifier.predict_and_apply(invoice)

      assert updated.prediction_status == :predicted
      updated = Invoices.get_invoice_with_details!(company.id, updated.id)
      assert updated.category_id == nil
      assert "monthly" in updated.tags
    end

    test "sets predicted when only category matches above category threshold", %{
      company: company
    } do
      {:ok, category} = Invoices.create_category(company.id, %{identifier: "finance:invoices"})

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

    test "applies category but not tag when confidence is between the two thresholds", %{
      company: company
    } do
      {:ok, category} = Invoices.create_category(company.id, %{identifier: "finance:invoices"})

      invoice = insert(:manual_invoice, company: company, type: :expense)

      # 0.80 is above category threshold (0.71) but below tag threshold (0.95)
      expect_predictions(
        category: %{
          "predicted_label" => "finance:invoices",
          "confidence" => 0.80,
          "model_version" => "v1.0",
          "probabilities" => %{"finance:invoices" => 0.80}
        },
        tag: %{
          "predicted_label" => "monthly",
          "confidence" => 0.80,
          "model_version" => "v1.0",
          "probabilities" => %{"monthly" => 0.80}
        }
      )

      assert {:ok, updated} = InvoiceClassifier.predict_and_apply(invoice)

      assert updated.prediction_status == :predicted
      updated = Invoices.get_invoice_with_details!(company.id, updated.id)
      assert updated.category_id == category.id
      assert updated.tags == []
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

    test "auto-applies at exact threshold boundaries", %{company: company} do
      {:ok, category} = Invoices.create_category(company.id, %{identifier: "finance:invoices"})

      invoice = insert(:manual_invoice, company: company, type: :expense)

      # Exactly at category threshold (0.71) and tag threshold (0.95)
      expect_predictions(
        category: %{
          "predicted_label" => "finance:invoices",
          "confidence" => @category_threshold,
          "model_version" => "v1.0",
          "probabilities" => %{"finance:invoices" => @category_threshold}
        },
        tag: %{
          "predicted_label" => "monthly",
          "confidence" => @tag_threshold,
          "model_version" => "v1.0",
          "probabilities" => %{"monthly" => @tag_threshold}
        }
      )

      assert {:ok, updated} = InvoiceClassifier.predict_and_apply(invoice)

      assert updated.prediction_status == :predicted
      updated = Invoices.get_invoice_with_details!(company.id, updated.id)
      assert updated.category_id == category.id
      assert "monthly" in updated.tags
    end

    test "does not apply when just below threshold boundaries", %{company: company} do
      {:ok, _category} = Invoices.create_category(company.id, %{identifier: "finance:invoices"})

      invoice = insert(:manual_invoice, company: company, type: :expense)

      # Just below both thresholds
      expect_predictions(
        category: %{
          "predicted_label" => "finance:invoices",
          "confidence" => @category_threshold - 0.01,
          "model_version" => "v1.0",
          "probabilities" => %{"finance:invoices" => @category_threshold - 0.01}
        },
        tag: %{
          "predicted_label" => "monthly",
          "confidence" => @tag_threshold - 0.01,
          "model_version" => "v1.0",
          "probabilities" => %{"monthly" => @tag_threshold - 0.01}
        }
      )

      assert {:ok, updated} = InvoiceClassifier.predict_and_apply(invoice)

      assert updated.prediction_status == :needs_review
      updated = Invoices.get_invoice_with_details!(company.id, updated.id)
      assert updated.category_id == nil
      assert updated.tags == []
    end

    test "stores full probability distributions even when below thresholds", %{company: company} do
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

      # Below thresholds and no matching company categories/tags -> needs_review
      assert updated.prediction_status == :needs_review
      assert updated.prediction_category_probabilities == cat_probs
      assert updated.prediction_tag_probabilities == tag_probs
      assert updated.prediction_category_model_version == "v2.1"
      assert updated.prediction_tag_model_version == "v2.1"
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

    test "no-ops when prediction_status is nil", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: :expense)
      assert invoice.prediction_status == nil

      assert {:ok, returned} = Invoices.mark_prediction_manual(invoice)
      assert returned.prediction_status == nil
    end

    test "no-ops when prediction_status is already manual", %{company: company} do
      invoice =
        insert(:manual_invoice,
          company: company,
          type: :expense,
          prediction_status: :manual
        )

      assert {:ok, returned} = Invoices.mark_prediction_manual(invoice)
      assert returned.prediction_status == :manual
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
