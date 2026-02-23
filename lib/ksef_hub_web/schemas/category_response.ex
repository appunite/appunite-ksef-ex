defmodule KsefHubWeb.Schemas.CategoryResponse do
  @moduledoc """
  OpenAPI response schema wrapping a single category in a `data` key.
  """

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "CategoryResponse",
    description: "Single category response.",
    type: :object,
    properties: %{
      data: KsefHubWeb.Schemas.Category
    },
    required: [:data]
  })
end
