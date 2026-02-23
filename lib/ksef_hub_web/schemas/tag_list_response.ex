defmodule KsefHubWeb.Schemas.TagListResponse do
  @moduledoc """
  OpenAPI response schema wrapping a list of tags in a `data` key.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "TagListResponse",
    description: "List of tags response.",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: KsefHubWeb.Schemas.Tag}
    },
    required: [:data]
  })
end
