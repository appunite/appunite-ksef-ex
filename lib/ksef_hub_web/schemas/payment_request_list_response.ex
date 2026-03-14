defmodule KsefHubWeb.Schemas.PaymentRequestListResponse do
  @moduledoc "Paginated list of payment requests response."

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PaymentRequestListResponse",
    description: "Paginated list of payment requests response.",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: KsefHubWeb.Schemas.PaymentRequest},
      meta: KsefHubWeb.Schemas.PaginationMeta
    },
    required: [:data, :meta]
  })
end
