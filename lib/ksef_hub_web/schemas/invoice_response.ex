defmodule KsefHubWeb.Schemas.InvoiceResponse do
  @moduledoc """
  OpenAPI response schema wrapping a single invoice in a `data` key.
  """

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "InvoiceResponse",
    description: "Single invoice response.",
    type: :object,
    properties: %{
      data: KsefHubWeb.Schemas.Invoice
    },
    required: [:data]
  })
end
