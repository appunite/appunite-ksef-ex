defmodule KsefHubWeb.Schemas.TagListResponse do
  @moduledoc """
  OpenAPI response schema wrapping a list of tag strings in a `data` key.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "TagListResponse",
    description: "List of distinct tag values used on invoices.",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: %Schema{type: :string}}
    },
    required: [:data]
  })
end
