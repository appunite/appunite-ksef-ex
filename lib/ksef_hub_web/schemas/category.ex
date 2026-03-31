defmodule KsefHubWeb.Schemas.Category do
  @moduledoc """
  OpenAPI schema for a category resource.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Category",
    description: "A category for classifying invoices. Identifier uses group:target format.",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Category UUID."},
      identifier: %Schema{
        type: :string,
        description: "Category identifier in group:target format (ML model key).",
        pattern: "^[^:]+:.+$",
        example: "operations:utilities"
      },
      name: %Schema{
        type: :string,
        nullable: true,
        description: "Human-readable display name.",
        example: "Utilities"
      },
      emoji: %Schema{type: :string, nullable: true, description: "Optional emoji icon."},
      description: %Schema{
        type: :string,
        nullable: true,
        description: "Optional description."
      },
      examples: %Schema{
        type: :string,
        nullable: true,
        description: "Example descriptions for this category."
      },
      sort_order: %Schema{
        type: :integer,
        description: "Sort order for display.",
        default: 0
      },
      default_cost_line: %Schema{
        type: :string,
        enum: ["growth", "heads", "service", "service_delivery", "client_success"],
        nullable: true,
        description:
          "Default cost line for invoices assigned to this category. Auto-populated when setting category."
      },
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :identifier, :sort_order],
    example: %{
      id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      identifier: "operations:utilities",
      name: "Utilities",
      emoji: "⚡",
      description: "Utility bills and related invoices",
      examples: "Electricity, water, gas bills",
      sort_order: 0,
      inserted_at: "2024-01-15T10:35:00Z",
      updated_at: "2024-01-15T10:35:00Z"
    }
  })
end
