defmodule KsefHubWeb.Schemas.Tag do
  @moduledoc """
  OpenAPI schema for a tag resource.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Tag",
    description: "A tag for annotating invoices.",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Tag UUID."},
      name: %Schema{type: :string, description: "Tag name."},
      description: %Schema{type: :string, nullable: true, description: "Optional description."},
      usage_count: %Schema{
        type: :integer,
        description: "Number of invoices using this tag.",
        minimum: 0
      },
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :name],
    example: %{
      id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      name: "urgent",
      description: "Requires immediate attention",
      usage_count: 12,
      inserted_at: "2024-01-15T10:35:00Z",
      updated_at: "2024-01-15T10:35:00Z"
    }
  })
end
