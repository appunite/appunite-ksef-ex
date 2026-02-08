defmodule KsefHubWeb.Schemas.MessageResponse do
  @moduledoc """
  OpenAPI response schema for endpoints that return a simple message string.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "MessageResponse",
    description: "Simple message response.",
    type: :object,
    properties: %{
      message: %Schema{type: :string}
    },
    required: [:message]
  })
end
