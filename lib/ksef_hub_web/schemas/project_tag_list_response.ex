defmodule KsefHubWeb.Schemas.ProjectTagListResponse do
  @moduledoc """
  OpenAPI response schema wrapping a list of project tag strings in a `data` key.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ProjectTagListResponse",
    description: "List of distinct project tag values.",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: %Schema{type: :string}}
    },
    required: [:data]
  })
end
