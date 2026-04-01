defmodule KsefHubWeb.Schemas.SetProjectTagRequest do
  @moduledoc """
  OpenAPI request schema for setting an invoice's project tag.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "SetProjectTagRequest",
    description: "Request body for setting an invoice's project tag.",
    type: :object,
    properties: %{
      project_tag: %Schema{
        type: :string,
        nullable: true,
        maxLength: 255,
        description: "Project tag to assign, or null to clear."
      }
    },
    required: [:project_tag],
    examples: [
      %{project_tag: "Project Alpha"},
      %{project_tag: nil}
    ]
  })
end
