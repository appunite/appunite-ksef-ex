defmodule KsefHubWeb.Schemas.TokenResponse do
  @moduledoc """
  OpenAPI response schema wrapping a single API token in a `data` key.
  """

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "TokenResponse",
    description: "Single token response.",
    type: :object,
    properties: %{
      data: KsefHubWeb.Schemas.Token
    },
    required: [:data]
  })
end
