defmodule KsefHubWeb.Schemas.UpdateTagRequest do
  @moduledoc """
  OpenAPI request schema for updating a tag.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "UpdateTagRequest",
    description: "Request body for updating a tag.",
    type: :object,
    properties: %{
      name: %Schema{type: :string, description: "Tag name."},
      type: %Schema{
        type: :string,
        enum: ["expense", "income"],
        description: "Tag type (expense or income)."
      },
      description: %Schema{type: :string, nullable: true, description: "Optional description."}
    },
    example: %{
      name: "urgent"
    }
  })
end
