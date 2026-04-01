defmodule KsefHubWeb.Schemas.SetTagsRequest do
  @moduledoc """
  OpenAPI request schema for setting tags on an invoice as a list of strings.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "SetTagsRequest",
    description: "List of tag strings to assign to an invoice. Pass an empty list to clear.",
    type: :object,
    properties: %{
      tags: %Schema{
        type: :array,
        items: %Schema{type: :string, maxLength: 100},
        maxItems: 50,
        description: "Tag names to assign. Up to 50 tags, each up to 100 characters."
      }
    },
    required: [:tags]
  })
end
