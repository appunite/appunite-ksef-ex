defmodule KsefHubWeb.Schemas.UpdateCategoryRequest do
  @moduledoc """
  OpenAPI request schema for updating a category.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "UpdateCategoryRequest",
    description: "Request body for updating a category.",
    type: :object,
    properties: %{
      name: %Schema{
        type: :string,
        description: "Category name in group:target format.",
        pattern: "^[^:]+:.+$"
      },
      emoji: %Schema{type: :string, nullable: true, description: "Optional emoji icon."},
      description: %Schema{type: :string, nullable: true, description: "Optional description."},
      sort_order: %Schema{type: :integer, description: "Sort order for display."}
    },
    example: %{
      name: "operations:utilities",
      emoji: "⚡"
    }
  })
end
