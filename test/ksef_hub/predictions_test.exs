defmodule KsefHub.PredictionsTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory
  import Mox

  alias KsefHub.Invoices
  alias KsefHub.Predictions

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
          type: "expense"
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

      assert {:ok, updated} = Predictions.predict_and_apply(invoice)

      assert updated.prediction_status == "predicted"
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

      invoice = insert(:manual_invoice, company: company, type: "expense")

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

      assert {:ok, updated} = Predictions.predict_and_apply(invoice)

      assert updated.prediction_status == "needs_review"
      assert updated.prediction_category_name == "finance:invoices"
      assert updated.prediction_category_confidence == 0.65

      # Category should NOT be applied
      assert updated.category_id == nil
    end

    test "skips non-expense invoices", %{company: company} do
      invoice = insert(:invoice, company: company, type: "income")

      assert {:skip, :not_expense} = Predictions.predict_and_apply(invoice)
    end

    test "sets needs_review when high confidence but no matching company category", %{
      company: company
    } do
      # No categories or tags created for this company
      invoice = insert(:manual_invoice, company: company, type: "expense")

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

      assert {:ok, updated} = Predictions.predict_and_apply(invoice)

      # High confidence but no match -> needs_review
      assert updated.prediction_status == "needs_review"
      assert updated.category_id == nil
    end

    test "handles prediction service errors gracefully", %{company: company} do
      invoice = insert(:manual_invoice, company: company, type: "expense")

      KsefHub.Predictions.Mock
      |> expect(:predict_category, fn _input ->
        {:error, {:prediction_service_error, 500}}
      end)

      assert {:error, {:prediction_service_error, 500}} =
               Predictions.predict_and_apply(invoice)
    end

    test "sets predicted when only category matches above threshold", %{company: company} do
      {:ok, category} = Invoices.create_category(company.id, %{name: "finance:invoices"})

      invoice = insert(:manual_invoice, company: company, type: "expense")

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

      assert {:ok, updated} = Predictions.predict_and_apply(invoice)

      assert updated.prediction_status == "predicted"
      updated = Invoices.get_invoice_with_details!(company.id, updated.id)
      assert updated.category_id == category.id
    end
  end

  @spec expect_predictions(keyword()) :: :ok
  defp expect_predictions(opts) do
    cat_result = Keyword.fetch!(opts, :category)
    tag_result = Keyword.fetch!(opts, :tag)

    KsefHub.Predictions.Mock
    |> expect(:predict_category, fn _input -> {:ok, cat_result} end)
    |> expect(:predict_tag, fn _input -> {:ok, tag_result} end)
  end
end
