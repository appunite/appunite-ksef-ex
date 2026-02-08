defmodule KsefHubWeb.Schemas.TokenListResponse do
  @moduledoc """
  OpenAPI response schema wrapping a list of API tokens in a `data` key.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "TokenListResponse",
    description: "List of API tokens response.",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: KsefHubWeb.Schemas.Token}
    },
    required: [:data]
  })
end
