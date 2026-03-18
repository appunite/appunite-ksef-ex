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
      sort_order: %Schema{type: :integer, description: "Sort order for display."}
    },
    example: %{
      identifier: "operations:utilities",
      name: "Utilities",
      emoji: "⚡"
    }
  })
end
