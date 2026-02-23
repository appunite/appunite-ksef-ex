defmodule KsefHubWeb.Schemas.SetCategoryRequest do
  @moduledoc """
  OpenAPI request schema for setting an invoice's category.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "SetCategoryRequest",
    description: "Request body for setting an invoice's category.",
    type: :object,
    properties: %{
      category_id: %Schema{
        type: :string,
        format: :uuid,
        nullable: true,
        description: "Category UUID to assign, or null to clear."
      }
    },
    required: [:category_id],
    example: %{
      category_id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    }
  })
end
