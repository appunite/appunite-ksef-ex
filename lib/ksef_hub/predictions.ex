defmodule KsefHub.Predictions do
  @moduledoc """
  Predictions context. Orchestrates ML-based category and tag prediction for
  expense invoices using the au-payroll-model-categories sidecar.

  Auto-applies predictions at >= 80% confidence when a matching category/tag
  exists in the company. Below threshold, predictions are stored for human review.
  """

  import Ecto.Query

  require Logger

  alias KsefHub.Invoices
  alias KsefHub.Invoices.{Category, Invoice, Tag}
  alias KsefHub.Repo

  @confidence_threshold 0.80

  @doc """
  Runs category and tag prediction for an expense invoice, then applies
  results based on confidence threshold.

  Returns `{:ok, invoice}` on success, `{:error, reason}` on failure,
  or `{:skip, reason}` when prediction is not applicable.
  """
  @spec predict_and_apply(Invoice.t()) ::
          {:ok, Invoice.t()} | {:error, term()} | {:skip, atom()}
  def predict_and_apply(%Invoice{type: :expense} = invoice) do
    input = build_input(invoice)

    with {:ok, cat_result} <- prediction_client().predict_category(input),
         {:ok, tag_result} <- prediction_client().predict_tag(input) do
      apply_predictions(invoice, cat_result, tag_result)
    end
  end

  def predict_and_apply(%Invoice{}), do: {:skip, :not_expense}

  @spec build_input(Invoice.t()) :: map()
  defp build_input(invoice) do
    %{
      entity_id: invoice.id,
      owner_id: invoice.company_id,
      net_price: to_float(invoice.net_amount),
      gross_price: to_float(invoice.gross_amount),
      currency: invoice.currency || "PLN",
      invoice_title: invoice.seller_name,
      tin: invoice.seller_nip,
      issue_date: Date.to_iso8601(invoice.issue_date)
    }
  end

  @spec apply_predictions(Invoice.t(), map(), map()) ::
          {:ok, Invoice.t()} | {:error, term()}
  defp apply_predictions(invoice, cat_result, tag_result) do
    resolution = resolve_predictions(invoice.company_id, cat_result, tag_result)
    persist_and_apply(invoice, resolution)
  end

  @spec resolve_predictions(Ecto.UUID.t(), map(), map()) :: map()
  defp resolve_predictions(company_id, cat_result, tag_result) do
    cat_name = cat_result["predicted_label"]
    cat_confidence = cat_result["confidence"] || 0.0
    tag_name = tag_result["predicted_label"]
    tag_confidence = tag_result["confidence"] || 0.0

    matching_category = find_category_by_name(company_id, cat_name)
    matching_tag = find_tag_by_name(company_id, tag_name)

    apply_category? = cat_confidence >= @confidence_threshold and matching_category != nil
    apply_tag? = tag_confidence >= @confidence_threshold and matching_tag != nil

    %{
      attrs: build_prediction_attrs(cat_result, tag_result, apply_category?, apply_tag?),
      category: if(apply_category?, do: matching_category),
      tag: if(apply_tag?, do: matching_tag)
    }
  end

  @spec build_prediction_attrs(map(), map(), boolean(), boolean()) :: map()
  defp build_prediction_attrs(cat_result, tag_result, apply_category?, apply_tag?) do
    status = if apply_category? or apply_tag?, do: :predicted, else: :needs_review

    %{
      prediction_status: status,
      prediction_category_name: cat_result["predicted_label"],
      prediction_tag_name: tag_result["predicted_label"],
      prediction_category_confidence: cat_result["confidence"] || 0.0,
      prediction_tag_confidence: tag_result["confidence"] || 0.0,
      prediction_model_version: cat_result["model_version"] || tag_result["model_version"],
      prediction_category_probabilities: cat_result["probabilities"],
      prediction_tag_probabilities: tag_result["probabilities"],
      prediction_predicted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }
  end

  @spec persist_and_apply(Invoice.t(), map()) :: {:ok, Invoice.t()} | {:error, term()}
  defp persist_and_apply(invoice, %{attrs: attrs, category: category, tag: tag}) do
    Repo.transaction(fn ->
      updated = update_prediction_fields!(invoice, attrs)
      if category, do: apply_category_safely(updated, category)
      if tag, do: apply_tag_safely(updated, tag)
      Repo.reload!(updated)
    end)
  end

  @spec update_prediction_fields!(Invoice.t(), map()) :: Invoice.t()
  defp update_prediction_fields!(invoice, attrs) do
    invoice
    |> Invoice.prediction_changeset(attrs)
    |> Repo.update!()
  end

  @spec apply_category_safely(Invoice.t(), Category.t()) :: :ok
  defp apply_category_safely(invoice, category) do
    case Invoices.set_invoice_category(invoice, category.id) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.warning("Failed to apply predicted category: #{inspect(reason)}")
    end
  end

  @spec apply_tag_safely(Invoice.t(), Tag.t()) :: :ok
  defp apply_tag_safely(invoice, tag) do
    case Invoices.add_invoice_tag(invoice.id, tag.id) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.warning("Failed to apply predicted tag: #{inspect(reason)}")
    end
  end

  @spec find_category_by_name(Ecto.UUID.t(), String.t() | nil) :: Category.t() | nil
  defp find_category_by_name(_company_id, nil), do: nil

  defp find_category_by_name(company_id, name) do
    Category
    |> where([c], c.company_id == ^company_id and c.name == ^name)
    |> Repo.one()
  end

  @spec find_tag_by_name(Ecto.UUID.t(), String.t() | nil) :: Tag.t() | nil
  defp find_tag_by_name(_company_id, nil), do: nil

  defp find_tag_by_name(company_id, name) do
    Tag
    |> where([t], t.company_id == ^company_id and t.name == ^name)
    |> Repo.one()
  end

  @spec to_float(Decimal.t() | nil) :: float()
  defp to_float(nil), do: 0.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)

  @spec prediction_client() :: module()
  defp prediction_client do
    Application.get_env(:ksef_hub, :prediction_client, KsefHub.Predictions.PredictionService)
  end
end
