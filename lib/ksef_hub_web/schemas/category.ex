defmodule KsefHubWeb.Schemas.Category do
  @moduledoc """
  OpenAPI schema for a category resource.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Category",
    description: "A category for classifying invoices. Name uses group:target format.",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Category UUID."},
      name: %Schema{
        type: :string,
        description: "Category name in group:target format.",
        pattern: "^[^:]+:.+$",
        example: "operations:utilities"
      },
      emoji: %Schema{type: :string, nullable: true, description: "Optional emoji icon."},
      description: %Schema{
        type: :string,
        nullable: true,
        description: "Optional description."
      },
      sort_order: %Schema{
        type: :integer,
        description: "Sort order for display.",
        default: 0
      },
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :name, :sort_order],
    example: %{
      id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      name: "operations:utilities",
      emoji: "⚡",
      description: "Utility bills and related invoices",
      sort_order: 0,
      inserted_at: "2024-01-15T10:35:00Z",
      updated_at: "2024-01-15T10:35:00Z"
    }
  })
end
