defmodule KsefHubWeb.Schemas.InvoiceListResponse do
  @moduledoc """
  OpenAPI response schema wrapping a list of invoices in a `data` key.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "InvoiceListResponse",
    description: "List of invoices response.",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: KsefHubWeb.Schemas.Invoice}
    },
    required: [:data]
  })
end
