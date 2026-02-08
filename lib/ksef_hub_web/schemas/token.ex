defmodule KsefHubWeb.Schemas.Token do
  @moduledoc """
  OpenAPI schema for an API token resource.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Token",
    description: "An API bearer token for authenticating REST requests.",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      name: %Schema{type: :string, description: "Human-readable token name."},
      description: %Schema{type: :string, nullable: true},
      token_prefix: %Schema{
        type: :string,
        description: "First characters of the token (for identification)."
      },
      expires_at: %Schema{type: :string, format: :"date-time", nullable: true},
      last_used_at: %Schema{type: :string, format: :"date-time", nullable: true},
      request_count: %Schema{type: :integer},
      is_active: %Schema{type: :boolean},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :name, :is_active]
  })
end
