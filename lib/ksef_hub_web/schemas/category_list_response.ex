defmodule KsefHubWeb.Schemas.CategoryListResponse do
  @moduledoc """
  OpenAPI response schema wrapping a list of categories in a `data` key.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CategoryListResponse",
    description: "List of categories response.",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: KsefHubWeb.Schemas.Category}
    },
    required: [:data]
  })
end
