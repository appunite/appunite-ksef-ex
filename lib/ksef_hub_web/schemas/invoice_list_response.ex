defmodule KsefHubWeb.Schemas.InvoiceListResponse do
  @moduledoc """
  OpenAPI response schema wrapping a list of invoices in a `data` key
  with pagination metadata in `meta`.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "InvoiceListResponse",
    description: "Paginated list of invoices response.",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: KsefHubWeb.Schemas.Invoice},
      meta: KsefHubWeb.Schemas.PaginationMeta
    },
    required: [:data, :meta]
  })
end
