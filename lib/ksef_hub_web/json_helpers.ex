defmodule KsefHubWeb.JsonHelpers do
  @moduledoc """
  Shared JSON serialization helpers for API controllers.

  Centralizes the conversion of domain structs to JSON-safe maps,
  eliminating duplication across controllers.
  """

  alias KsefHub.Invoices.{Category, Tag}
  alias KsefHub.PaymentRequests.PaymentRequest

  @doc "Serializes a category struct to a JSON-safe map."
  @spec category_json(Category.t()) :: map()
  def category_json(category) do
    %{
      id: category.id,
      name: category.name,
      emoji: category.emoji,
      description: category.description,
      sort_order: category.sort_order,
      inserted_at: category.inserted_at,
      updated_at: category.updated_at
    }
  end

  @doc "Serializes a tag struct to a JSON-safe map."
  @spec tag_json(Tag.t()) :: map()
  def tag_json(tag) do
    %{
      id: tag.id,
      name: tag.name,
      type: to_string(tag.type),
      description: tag.description,
      usage_count: Map.get(tag, :usage_count, 0),
      inserted_at: tag.inserted_at,
      updated_at: tag.updated_at
    }
  end

  @doc "Serializes a payment request struct to a JSON-safe map."
  @spec payment_request_json(PaymentRequest.t()) :: map()
  def payment_request_json(pr) do
    %{
      id: pr.id,
      recipient_name: pr.recipient_name,
      recipient_address: pr.recipient_address,
      amount: pr.amount && Decimal.to_string(pr.amount),
      currency: pr.currency,
      title: pr.title,
      iban: pr.iban,
      note: pr.note,
      status: pr.status,
      paid_at: pr.paid_at,
      invoice_id: pr.invoice_id,
      inserted_at: pr.inserted_at,
      updated_at: pr.updated_at
    }
  end

  @doc """
  Converts string-keyed params to atom-keyed maps, filtering to allowed keys only.

  Uses `String.to_existing_atom/1` to prevent atom exhaustion.
  """
  @spec atomize_keys(map(), [String.t()]) :: map()
  def atomize_keys(params, allowed_keys) do
    for {key, value} <- params,
        key in allowed_keys,
        into: %{} do
      {String.to_existing_atom(key), value}
    end
  end
end
