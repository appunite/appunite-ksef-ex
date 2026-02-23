defmodule KsefHubWeb.JsonHelpers do
  @moduledoc """
  Shared JSON serialization helpers for API controllers.

  Centralizes the conversion of domain structs to JSON-safe maps,
  eliminating duplication across controllers.
  """

  alias KsefHub.Invoices.{Category, Tag}

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
      description: tag.description,
      usage_count: Map.get(tag, :usage_count, 0),
      inserted_at: tag.inserted_at,
      updated_at: tag.updated_at
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
