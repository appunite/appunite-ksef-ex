defmodule KsefHubWeb.Schemas.CreateTagRequest do
  @moduledoc """
  OpenAPI request schema for creating a tag.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CreateTagRequest",
    description: "Request body for creating a tag.",
    type: :object,
    properties: %{
      name: %Schema{type: :string, description: "Tag name."},
      description: %Schema{type: :string, nullable: true, description: "Optional description."}
    },
    required: [:name],
    example: %{
      name: "urgent",
      description: "Requires immediate attention"
    }
  })
end
