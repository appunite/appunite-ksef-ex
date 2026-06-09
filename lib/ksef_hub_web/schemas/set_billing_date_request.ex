defmodule KsefHubWeb.Schemas.SetBillingDateRequest do
  @moduledoc """
  OpenAPI request schema for setting an invoice's billing period.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "SetBillingDateRequest",
    description:
      "Request body for setting an invoice's billing period. Editable on all invoices, including KSeF-synced ones, because billing period is an internal field.",
    type: :object,
    properties: %{
      billing_date_from: %Schema{
        type: :string,
        format: :date,
        nullable: true,
        pattern: "^\\d{4}-\\d{2}-01$",
        description:
          "Start of billing period (first day of month, YYYY-MM-01). Null clears the value."
      },
      billing_date_to: %Schema{
        type: :string,
        format: :date,
        nullable: true,
        pattern: "^\\d{4}-\\d{2}-01$",
        description:
          "End of billing period (first day of month, YYYY-MM-01). Must be >= billing_date_from. Null clears the value."
      }
    },
    required: [:billing_date_from, :billing_date_to],
    examples: [
      %{billing_date_from: "2026-05-01", billing_date_to: "2026-05-01"},
      %{billing_date_from: "2026-01-01", billing_date_to: "2026-03-01"},
      %{billing_date_from: nil, billing_date_to: nil}
    ]
  })
end
