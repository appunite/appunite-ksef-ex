defmodule KsefHubWeb.Schemas.PaginationMeta do
  @moduledoc """
  OpenAPI schema for pagination metadata returned alongside list responses.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PaginationMeta",
    description: "Pagination metadata for list endpoints.",
    type: :object,
    properties: %{
      page: %Schema{type: :integer, minimum: 1, description: "Current page number (1-based)."},
      per_page: %Schema{
        type: :integer,
        minimum: 1,
        maximum: 100,
        description: "Number of results per page."
      },
      total_count: %Schema{
        type: :integer,
        minimum: 0,
        description: "Total number of matching records."
      },
      total_pages: %Schema{
        type: :integer,
        minimum: 1,
        description: "Total number of pages."
      }
    },
    required: [:page, :per_page, :total_count, :total_pages],
    example: %{
      page: 1,
      per_page: 25,
      total_count: 142,
      total_pages: 6
    }
  })
end
