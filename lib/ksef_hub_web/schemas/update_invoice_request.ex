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
      vat_amount: %Schema{type: :string, description: "VAT amount as decimal string."},
      gross_amount: %Schema{type: :string, description: "Gross amount as decimal string."},
      currency: %Schema{type: :string, description: "ISO 4217 currency code.", example: "PLN"}
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
