defmodule KsefHubWeb.Schemas.PaymentRequestResponse do
  @moduledoc "Single payment request response."

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "PaymentRequestResponse",
    description: "Single payment request response.",
    type: :object,
    properties: %{
      data: KsefHubWeb.Schemas.PaymentRequest
    },
    required: [:data]
  })
end
