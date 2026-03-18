defmodule KsefHubWeb.Schemas.UpdateInvoiceRequest do
  @moduledoc """
  OpenAPI request schema for updating a pdf_upload invoice.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "UpdateInvoiceRequest",
    description:
      "Request body for updating a pdf_upload invoice. All fields are optional — only provided fields are updated.",
    type: :object,
    properties: %{
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
      currency: %Schema{type: :string, description: "ISO 4217 currency code.", example: "PLN"},
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
      billing_date: %Schema{
        type: :string,
        format: :date,
        nullable: true,
        pattern: "^\\d{4}-\\d{2}-01$",
        description:
          "Accounting period date (first day of month, YYYY-MM-01). Overrides auto-computed value."
      },
      iban: %Schema{
        type: :string,
        nullable: true,
        maxLength: 34,
        description: "Seller's bank account number (IBAN)."
      }
    },
    example: %{
      seller_nip: "1234567890",
      seller_name: "Dostawca Sp. z o.o.",
      issue_date: "2026-02-20",
      net_amount: "5000.00",
      gross_amount: "6150.00"
    }
  })
end
