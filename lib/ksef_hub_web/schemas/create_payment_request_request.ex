defmodule KsefHubWeb.Schemas.CreatePaymentRequestRequest do
  @moduledoc "Request body for creating a payment request."

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CreatePaymentRequestRequest",
    description: "Request body for creating a payment request.",
    type: :object,
    properties: %{
      recipient_name: %Schema{type: :string, description: "Name of the payment recipient."},
      recipient_address: %Schema{
        type: :object,
        nullable: true,
        description: "Recipient address.",
        properties: %{
          street: %Schema{type: :string, nullable: true},
          city: %Schema{type: :string, nullable: true},
          postal_code: %Schema{type: :string, nullable: true},
          country: %Schema{type: :string, nullable: true}
        }
      },
      amount: %Schema{type: :string, description: "Decimal amount as string."},
      currency: %Schema{
        type: :string,
        description: "ISO 4217 currency code.",
        default: "PLN"
      },
      title: %Schema{type: :string, description: "Bank transfer title."},
      iban: %Schema{
        type: :string,
        description: "Recipient IBAN (15-34 characters).",
        minLength: 15,
        maxLength: 34
      },
      invoice_id: %Schema{
        type: :string,
        format: :uuid,
        nullable: true,
        description: "Optional linked invoice UUID."
      }
    },
    required: [:recipient_name, :amount, :title, :iban],
    example: %{
      recipient_name: "Dostawca Sp. z o.o.",
      amount: "1230.00",
      currency: "PLN",
      title: "Invoice FV/2026/001",
      iban: "PL61109010140000071219812874"
    }
  })
end
