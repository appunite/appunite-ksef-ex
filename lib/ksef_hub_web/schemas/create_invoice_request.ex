defmodule KsefHubWeb.Schemas.CreateInvoiceRequest do
  @moduledoc """
  OpenAPI request schema for creating a manual invoice.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CreateInvoiceRequest",
    description: "Request body for creating a manual invoice.",
    type: :object,
    properties: %{
      type: %Schema{
        type: :string,
        enum: ["income", "expense"],
        description: "Invoice type."
      },
      ksef_number: %Schema{
        type: :string,
        nullable: true,
        description:
          "Optional KSeF reference number. If provided and matches an existing invoice, the new invoice is flagged as a suspected duplicate."
      },
      seller_nip: %Schema{
        type: :string,
        pattern: "^\\d{10}$",
        description: "Seller 10-digit NIP."
      },
      seller_name: %Schema{type: :string, description: "Seller name."},
      buyer_nip: %Schema{
        type: :string,
        pattern: "^\\d{10}$",
        description: "Buyer 10-digit NIP."
      },
      buyer_name: %Schema{type: :string, description: "Buyer name."},
      invoice_number: %Schema{type: :string, description: "Sequential invoice number."},
      issue_date: %Schema{type: :string, format: :date, description: "Invoice issue date."},
      net_amount: %Schema{type: :string, description: "Net amount as decimal string."},
      gross_amount: %Schema{type: :string, description: "Gross amount as decimal string."},
      currency: %Schema{
        type: :string,
        description: "ISO 4217 currency code.",
        default: "PLN",
        example: "PLN"
      },
      purchase_order: %Schema{
        type: :string,
        nullable: true,
        maxLength: 256,
        description: "Purchase order identifier."
      },
      sales_date: %Schema{
        type: :string,
        format: :date,
        nullable: true,
        description: "Sales/delivery date."
      },
      due_date: %Schema{
        type: :string,
        format: :date,
        nullable: true,
        description: "Payment due date."
      },
      iban: %Schema{
        type: :string,
        nullable: true,
        maxLength: 34,
        description: "Seller's bank account number (IBAN)."
      }
    },
    required: [
      :type,
      :seller_nip,
      :seller_name,
      :buyer_nip,
      :buyer_name,
      :invoice_number,
      :issue_date,
      :net_amount,
      :gross_amount
    ],
    example: %{
      type: "expense",
      seller_nip: "1234567890",
      seller_name: "Dostawca Sp. z o.o.",
      buyer_nip: "0987654321",
      buyer_name: "Nasza Firma S.A.",
      invoice_number: "FV/2026/042",
      issue_date: "2026-02-20",
      net_amount: "5000.00",
      gross_amount: "6150.00",
      currency: "PLN"
    }
  })
end
