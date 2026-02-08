defmodule KsefHubWeb.Schemas.TokenCreatedResponse do
  @moduledoc """
  OpenAPI response schema for a newly created API token.

  Includes the full plain-text token value (shown only once at creation)
  alongside the standard token fields and a user-facing message.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "TokenCreatedResponse",
    description: "Response after creating a new token. Contains the plain token shown only once.",
    type: :object,
    properties: %{
      data: %Schema{
        type: :object,
        allOf: [
          KsefHubWeb.Schemas.Token,
          %Schema{
            type: :object,
            properties: %{
              token: %Schema{
                type: :string,
                description: "Full token value. Shown only once at creation."
              }
            },
            required: [:token]
          }
        ]
      },
      message: %Schema{type: :string}
    },
    required: [:data, :message]
  })
end
