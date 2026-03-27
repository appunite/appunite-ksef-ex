defmodule KsefHub.InvoiceClassifier do
  @moduledoc """
  Invoice classification context. Orchestrates ML-based category and tag
  prediction for expense invoices using the au-payroll-model-categories sidecar.

  Auto-applies predictions when confidence meets configurable thresholds:
  - Category: default 71%, set via `CATEGORY_CONFIDENCE_THRESHOLD` env var
  - Tag: default 85%, set via `TAG_CONFIDENCE_THRESHOLD` env var

  When confidence meets the threshold and a matching category/tag exists in
  the company, the prediction is auto-applied. Below threshold, predictions
  are stored for human review.
  """

  import Ecto.Query

  require Logger

  alias KsefHub.Invoices
  alias KsefHub.Invoices.{Category, Invoice, Tag}
  alias KsefHub.Repo

  @doc "Returns the current category confidence threshold (0.0–1.0) from application config."
  @spec category_confidence_threshold() :: float()
  def category_confidence_threshold,
    do: Application.get_env(:ksef_hub, :category_confidence_threshold, 0.71)

  @doc "Returns the current tag confidence threshold (0.0–1.0) from application config."
  @spec tag_confidence_threshold() :: float()
  def tag_confidence_threshold,
    do: Application.get_env(:ksef_hub, :tag_confidence_threshold, 0.85)

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
    client = invoice_classifier()

    cat_task =
      Task.Supervisor.async_nolink(KsefHub.TaskSupervisor, fn ->
        client.predict_category(input)
      end)

    tag_task =
      Task.Supervisor.async_nolink(KsefHub.TaskSupervisor, fn ->
        client.predict_tag(input)
      end)

    [cat_result, tag_result] =
      [cat_task, tag_task]
      |> Task.yield_many(:timer.seconds(20))
      |> Enum.map(fn
        {_task, {:ok, result}} ->
          result

        {task, nil} ->
          Task.shutdown(task, :brutal_kill)
          {:error, :timeout}

        {_task, {:exit, reason}} ->
          {:error, {:task_failed, reason}}
      end)

    with {:ok, cat} <- cat_result,
         {:ok, tag} <- tag_result do
      apply_predictions(invoice, cat, tag)
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
    cat_identifier = cat_result["predicted_label"]
    cat_confidence = cat_result["confidence"] || 0.0
    tag_name = tag_result["predicted_label"]
    tag_confidence = tag_result["confidence"] || 0.0

    matching_category = find_category_by_identifier(company_id, cat_identifier)
    matching_tag = find_tag_by_name(company_id, tag_name)

    confident_category? = cat_confidence >= category_confidence_threshold() and matching_category != nil
    confident_tag? = tag_confidence >= tag_confidence_threshold() and matching_tag != nil

    %{
      attrs: build_prediction_attrs(cat_result, tag_result, confident_category?, confident_tag?),
      category: if(confident_category?, do: matching_category),
      tag: if(confident_tag?, do: matching_tag)
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

  @spec find_category_by_identifier(Ecto.UUID.t(), String.t() | nil) :: Category.t() | nil
  defp find_category_by_identifier(_company_id, nil), do: nil

  defp find_category_by_identifier(company_id, identifier) do
    Category
    |> where([c], c.company_id == ^company_id and c.identifier == ^identifier)
    |> Repo.one()
  end

  @spec find_tag_by_name(Ecto.UUID.t(), String.t() | nil) :: Tag.t() | nil
  defp find_tag_by_name(_company_id, nil), do: nil

  defp find_tag_by_name(company_id, name) do
    Tag
    |> where([t], t.company_id == ^company_id and t.name == ^name and t.type == :expense)
    |> Repo.one()
  end

  @spec to_float(Decimal.t() | nil) :: float()
  defp to_float(nil), do: 0.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)

  @spec invoice_classifier() :: module()
  defp invoice_classifier do
    Application.get_env(:ksef_hub, :invoice_classifier, KsefHub.InvoiceClassifier.Client)
  end
end
