defmodule KsefHubWeb.Schemas.AccessGrant do
  @moduledoc "OpenAPI schema for an invoice access grant."

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AccessGrant",
    description: "A grant giving a user access to a restricted invoice.",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Grant UUID."},
      invoice_id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      user_name: %Schema{type: :string, nullable: true, description: "Name of the granted user."},
      user_email: %Schema{type: :string, description: "Email of the granted user."},
      granted_by_id: %Schema{
        type: :string,
        format: :uuid,
        nullable: true,
        description: "User who granted the access."
      },
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :invoice_id, :user_id, :user_email]
  })
end
