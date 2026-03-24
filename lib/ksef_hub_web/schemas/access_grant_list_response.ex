defmodule KsefHubWeb.Schemas.AccessGrantListResponse do
  @moduledoc "OpenAPI schema for a list of access grants response."

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AccessGrantListResponse",
    description: "Response containing access control status and grants for an invoice.",
    type: :object,
    properties: %{
      data: %Schema{
        type: :object,
        properties: %{
          access_restricted: %Schema{
            type: :boolean,
            description: "Whether access is restricted to granted users only."
          },
          grants: %Schema{
            type: :array,
            items: KsefHubWeb.Schemas.AccessGrant,
            description: "List of access grants."
          }
        },
        required: [:access_restricted, :grants]
      }
    },
    required: [:data]
  })
end
