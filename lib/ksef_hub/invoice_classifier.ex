defmodule KsefHub.InvoiceClassifier do
  @moduledoc """
  Invoice classification context. Orchestrates ML-based category and tag
  prediction for invoices using the company's configured classifier service.

  Auto-applies predictions when confidence meets the company's configured thresholds:
  - Category threshold: configurable per company (default 0.71)
  - Tag threshold: configurable per company (default 0.95)

  Categories require a matching record in the company to be auto-applied.
  Tags are free-form strings — all tags from the probability distribution
  that meet the threshold are applied (multi-label), not just the top one.
  Below threshold, predictions are stored for human review.
  """

  import Ecto.Query

  require Logger

  alias KsefHub.Credentials.Encryption
  alias KsefHub.Invoices
  alias KsefHub.Invoices.{Category, Invoice}
  alias KsefHub.Repo
  alias KsefHub.ServiceConfig
  alias KsefHub.ServiceConfig.ClassifierConfig

  @doc "Returns the confidence thresholds for a company from its ClassifierConfig."
  @spec thresholds_for_company(Ecto.UUID.t()) :: {float(), float()}
  def thresholds_for_company(company_id) do
    case ServiceConfig.get_classifier_config(company_id) do
      %ClassifierConfig{
        category_confidence_threshold: cat,
        tag_confidence_threshold: tag
      }
      when is_float(cat) and is_float(tag) ->
        {cat, tag}

      _ ->
        {ClassifierConfig.default_category_threshold(), ClassifierConfig.default_tag_threshold()}
    end
  end

  @doc """
  Runs category and tag prediction for an expense invoice using the given
  classifier config, then applies results based on confidence thresholds.

  Returns `{:ok, invoice}` on success, `{:error, reason}` on failure,
  or `{:skip, reason}` when prediction is not applicable.
  """
  @spec predict_and_apply(Invoice.t(), ClassifierConfig.t()) ::
          {:ok, Invoice.t()} | {:error, term()} | {:skip, atom()}
  def predict_and_apply(%Invoice{type: :expense} = invoice, %ClassifierConfig{} = config) do
    client_config = build_client_config(config)
    input = build_input(invoice)
    client = invoice_classifier()

    cat_task =
      Task.Supervisor.async_nolink(KsefHub.TaskSupervisor, fn ->
        client.predict_category(input, client_config)
      end)

    tag_task =
      Task.Supervisor.async_nolink(KsefHub.TaskSupervisor, fn ->
        client.predict_tag(input, client_config)
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
      apply_predictions(invoice, cat, tag, config)
    end
  end

  def predict_and_apply(%Invoice{}, _config), do: {:skip, :not_expense}

  @spec build_client_config(ClassifierConfig.t()) :: map()
  defp build_client_config(%ClassifierConfig{} = config) do
    %{
      url: config.url,
      api_token: decrypt_token(config.api_token_encrypted)
    }
  end

  @spec decrypt_token(binary() | nil) :: String.t() | nil
  defp decrypt_token(nil), do: nil

  defp decrypt_token(encrypted) do
    case Encryption.decrypt(encrypted) do
      {:ok, token} -> token
      {:error, _} -> nil
    end
  end

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

  @spec apply_predictions(Invoice.t(), map(), map(), ClassifierConfig.t()) ::
          {:ok, Invoice.t()} | {:error, term()}
  defp apply_predictions(invoice, cat_result, tag_result, config) do
    resolution = resolve_predictions(invoice.company_id, cat_result, tag_result, config)
    persist_and_apply(invoice, resolution)
  end

  @spec resolve_predictions(Ecto.UUID.t(), map(), map(), ClassifierConfig.t()) :: map()
  defp resolve_predictions(company_id, cat_result, tag_result, config) do
    cat_identifier = cat_result["predicted_label"]
    cat_confidence = cat_result["confidence"] || 0.0

    matching_category = find_category_by_identifier(company_id, cat_identifier)

    cat_threshold = config.category_confidence_threshold || ClassifierConfig.default_category_threshold()

    confident_category? =
      cat_confidence >= cat_threshold and matching_category != nil

    tag_threshold = config.tag_confidence_threshold || ClassifierConfig.default_tag_threshold()
    confident_tags = extract_confident_tags(tag_result, tag_threshold)

    %{
      attrs:
        build_prediction_attrs(
          cat_result,
          tag_result,
          confident_category?,
          confident_tags != []
        ),
      category: if(confident_category?, do: matching_category),
      tag_names: confident_tags
    }
  end

  @spec extract_confident_tags(map(), float()) :: [String.t()]
  defp extract_confident_tags(tag_result, threshold) do
    (tag_result["probabilities"] || %{})
    |> Enum.filter(fn {_tag, prob} -> prob >= threshold end)
    |> Enum.sort_by(fn {_tag, prob} -> prob end, :desc)
    |> Enum.map(fn {tag, _prob} -> tag end)
    |> Enum.map(&normalize_tag_label/1)
    |> Enum.reject(&is_nil/1)
  end

  @spec normalize_tag_label(String.t() | nil) :: String.t() | nil
  defp normalize_tag_label(nil), do: nil

  defp normalize_tag_label(label) when is_binary(label) do
    trimmed = String.trim(label)
    if trimmed != "" and String.length(trimmed) <= Invoice.max_tag_length(), do: trimmed
  end

  defp normalize_tag_label(_), do: nil

  @spec build_prediction_attrs(map(), map(), boolean(), boolean()) :: map()
  defp build_prediction_attrs(cat_result, tag_result, apply_category?, apply_tag?) do
    status = if apply_category? or apply_tag?, do: :predicted, else: :needs_review

    %{
      prediction_status: status,
      prediction_expense_category_name: cat_result["predicted_label"],
      prediction_expense_tag_name: tag_result["predicted_label"],
      prediction_expense_category_confidence: cat_result["confidence"] || 0.0,
      prediction_expense_tag_confidence: tag_result["confidence"] || 0.0,
      prediction_expense_category_model_version: cat_result["model_version"],
      prediction_expense_tag_model_version: tag_result["model_version"],
      prediction_expense_category_probabilities: cat_result["probabilities"],
      prediction_expense_tag_probabilities: tag_result["probabilities"],
      prediction_predicted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }
  end

  @spec persist_and_apply(Invoice.t(), map()) :: {:ok, Invoice.t()} | {:error, term()}
  defp persist_and_apply(invoice, %{attrs: attrs, category: category, tag_names: tag_names}) do
    Repo.transaction(fn ->
      updated = update_prediction_fields!(invoice, attrs)
      cat_applied = if category, do: apply_category_safely(updated, category), else: false
      tags_applied = tag_names |> Enum.map(&apply_tag_safely(updated, &1)) |> Enum.any?()

      final = Repo.reload!(updated)

      # Recompute status based on what actually applied
      actual_status = if cat_applied or tags_applied, do: :predicted, else: :needs_review

      if actual_status != attrs[:prediction_status] do
        final
        |> Invoice.prediction_changeset(%{prediction_status: actual_status})
        |> Repo.update!()
      else
        final
      end
    end)
  end

  @spec update_prediction_fields!(Invoice.t(), map()) :: Invoice.t()
  defp update_prediction_fields!(invoice, attrs) do
    invoice
    |> Invoice.prediction_changeset(attrs)
    |> Repo.update!()
  end

  @spec apply_category_safely(Invoice.t(), Category.t()) :: boolean()
  defp apply_category_safely(invoice, category) do
    case Invoices.set_invoice_category(invoice, category.id) do
      {:ok, _} ->
        true

      {:error, reason} ->
        Logger.warning("Failed to apply predicted category: #{inspect(reason)}")
        false
    end
  end

  @spec apply_tag_safely(Invoice.t(), String.t()) :: boolean()
  defp apply_tag_safely(invoice, tag_name) do
    {:ok, updated} = Invoices.add_invoice_tag(invoice, tag_name)
    tag_name in (updated.tags || [])
  rescue
    e ->
      Logger.warning("Failed to apply predicted tag: #{Exception.message(e)}")
      false
  end

  @spec find_category_by_identifier(Ecto.UUID.t(), String.t() | nil) :: Category.t() | nil
  defp find_category_by_identifier(_company_id, nil), do: nil

  defp find_category_by_identifier(company_id, identifier) do
    Category
    |> where([c], c.company_id == ^company_id and c.identifier == ^identifier)
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
