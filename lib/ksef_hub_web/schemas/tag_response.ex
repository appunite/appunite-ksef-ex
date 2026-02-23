defmodule KsefHubWeb.Schemas.TagResponse do
  @moduledoc """
  OpenAPI response schema wrapping a single tag in a `data` key.
  """

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "TagResponse",
    description: "Single tag response.",
    type: :object,
    properties: %{
      data: KsefHubWeb.Schemas.Tag
    },
    required: [:data]
  })
end
