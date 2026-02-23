defmodule KsefHubWeb.Schemas.CreateCategoryRequest do
  @moduledoc """
  OpenAPI request schema for creating a category.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CreateCategoryRequest",
    description: "Request body for creating a category.",
    type: :object,
    properties: %{
      name: %Schema{
        type: :string,
        description: "Category name in group:target format.",
        pattern: "^[^:]+:.+$"
      },
      emoji: %Schema{type: :string, nullable: true, description: "Optional emoji icon."},
      description: %Schema{type: :string, nullable: true, description: "Optional description."},
      sort_order: %Schema{
        type: :integer,
        description: "Sort order for display.",
        default: 0
      }
    },
    required: [:name],
    example: %{
      name: "operations:utilities",
      emoji: "⚡",
      description: "Utility bills and related invoices",
      sort_order: 0
    }
  })
end
