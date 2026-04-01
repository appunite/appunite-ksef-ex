defmodule KsefHubWeb.Schemas.PaymentRequest do
  @moduledoc "OpenAPI schema for a payment request resource."

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PaymentRequest",
    description: "A payment request (wire transfer instruction).",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Payment Request UUID."},
      company_id: %Schema{type: :string, format: :uuid, description: "Company UUID."},
      recipient_name: %Schema{type: :string, description: "Name of the payment recipient."},
      recipient_nip: %Schema{
        type: :string,
        nullable: true,
        description: "Recipient NIP (tax identification number)."
      },
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
      currency: %Schema{type: :string, description: "ISO 4217 currency code.", example: "PLN"},
      title: %Schema{type: :string, description: "Bank transfer title."},
      iban: %Schema{
        type: :string,
        description: "Recipient IBAN (15-34 characters).",
        minLength: 15,
        maxLength: 34
      },
      status: %Schema{type: :string, enum: ["pending", "paid", "voided"]},
      note: %Schema{type: :string, nullable: true, description: "Optional internal note."},
      paid_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "When the payment was marked as paid."
      },
      voided_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "When the payment request was voided."
      },
      invoice_id: %Schema{
        type: :string,
        format: :uuid,
        nullable: true,
        description: "Linked invoice UUID."
      },
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :recipient_name, :amount, :currency, :title, :iban, :status],
    example: %{
      id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      recipient_name: "Dostawca Sp. z o.o.",
      recipient_address: %{
        street: "ul. Testowa 1",
        city: "Warszawa",
        postal_code: "00-001",
        country: "PL"
      },
      amount: "1230.00",
      currency: "PLN",
      title: "Invoice FV/2026/001",
      iban: "PL61109010140000071219812874",
      status: "pending",
      invoice_id: nil,
      inserted_at: "2026-03-14T10:35:00Z",
      updated_at: "2026-03-14T10:35:00Z"
    }
  })
end
