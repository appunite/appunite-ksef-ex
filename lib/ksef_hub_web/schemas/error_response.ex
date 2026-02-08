defmodule KsefHubWeb.Schemas.ErrorResponse do
  @moduledoc """
  OpenAPI response schema for error responses.

  The `error` field is either a string message or an object of
  field-level validation errors (from Ecto changeset traversal).
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ErrorResponse",
    description: "Error response.",
    type: :object,
    properties: %{
      error: %Schema{
        oneOf: [
          %Schema{type: :string, description: "Error message."},
          %Schema{type: :object, description: "Field-level validation errors."}
        ]
      }
    },
    required: [:error]
  })
end
