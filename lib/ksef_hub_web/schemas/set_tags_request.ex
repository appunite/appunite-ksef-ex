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
        items: %Schema{type: :string},
        description: "Tag names to assign."
      }
    },
    required: [:tags]
  })
end
