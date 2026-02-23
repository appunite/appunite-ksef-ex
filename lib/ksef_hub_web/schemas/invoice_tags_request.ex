defmodule KsefHubWeb.Schemas.InvoiceTagsRequest do
  @moduledoc """
  OpenAPI request schema for adding or setting tags on an invoice.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "InvoiceTagsRequest",
    description: "Request body for managing invoice tags.",
    type: :object,
    properties: %{
      tag_ids: %Schema{
        type: :array,
        items: %Schema{type: :string, format: :uuid},
        description: "List of tag UUIDs."
      }
    },
    required: [:tag_ids],
    example: %{
      tag_ids: ["a1b2c3d4-e5f6-7890-abcd-ef1234567890"]
    }
  })
end
