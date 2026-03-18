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
      identifier: %Schema{
        type: :string,
        description: "Category identifier in group:target format.",
        pattern: "^[^:]+:.+$"
      },
      name: %Schema{
        type: :string,
        nullable: true,
        description: "Human-readable display name."
      },
      emoji: %Schema{type: :string, nullable: true, description: "Optional emoji icon."},
      description: %Schema{type: :string, nullable: true, description: "Optional description."},
      examples: %Schema{
        type: :string,
        nullable: true,
        description: "Example descriptions for this category."
      },
      sort_order: %Schema{
        type: :integer,
        description: "Sort order for display.",
        default: 0
      }
    },
    required: [:identifier],
    example: %{
      identifier: "operations:utilities",
      name: "Utilities",
      emoji: "⚡",
      description: "Utility bills and related invoices",
      sort_order: 0
    }
  })
end
