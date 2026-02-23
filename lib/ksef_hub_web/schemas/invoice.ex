defmodule KsefHubWeb.Schemas.Invoice do
  @moduledoc """
  OpenAPI schema for an invoice resource.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Invoice",
    description: "A KSeF invoice (income or expense).",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Invoice UUID."},
      ksef_number: %Schema{
        type: :string,
        nullable: true,
        description: "KSeF reference number assigned by the government system."
      },
      type: %Schema{type: :string, enum: ["income", "expense"]},
      seller_nip: %Schema{
        type: :string,
        pattern: "^\\d{10}$",
        description: "Seller 10-digit NIP."
      },
      seller_name: %Schema{type: :string},
      buyer_nip: %Schema{type: :string, pattern: "^\\d{10}$", description: "Buyer 10-digit NIP."},
      buyer_name: %Schema{type: :string},
      invoice_number: %Schema{type: :string, description: "Sequential invoice number."},
      issue_date: %Schema{type: :string, format: :date},
      net_amount: %Schema{type: :string, description: "Decimal as string."},
      vat_amount: %Schema{type: :string, description: "Decimal as string."},
      gross_amount: %Schema{type: :string, description: "Decimal as string."},
      currency: %Schema{type: :string, description: "ISO 4217 currency code.", example: "PLN"},
      status: %Schema{type: :string, enum: ["pending", "approved", "rejected"]},
      source: %Schema{
        type: :string,
        enum: ["ksef", "manual"],
        description: "Invoice origin: synced from KSeF or manually created."
      },
      category_id: %Schema{
        type: :string,
        format: :uuid,
        nullable: true,
        description: "ID of the assigned category."
      },
      category: %Schema{
        nullable: true,
        description: "Category details (included in show response).",
        allOf: [KsefHubWeb.Schemas.Category]
      },
      tags: %Schema{
        type: :array,
        items: KsefHubWeb.Schemas.Tag,
        description: "Tags assigned to this invoice (included in show response)."
      },
      duplicate_of_id: %Schema{
        type: :string,
        format: :uuid,
        nullable: true,
        description: "ID of the original invoice this is a duplicate of."
      },
      duplicate_status: %Schema{
        type: :string,
        enum: ["suspected", "confirmed", "dismissed"],
        nullable: true,
        description: "Duplicate review status. Only set when duplicate_of_id is present."
      },
      ksef_acquisition_date: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "When KSeF received the invoice."
      },
      permanent_storage_date: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "When the invoice entered permanent KSeF storage."
      },
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :type, :status, :seller_nip, :buyer_nip, :issue_date],
    example: %{
      id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      ksef_number: "1234567890-20240101-ABC123DEF456-78",
      type: "income",
      seller_nip: "1234567890",
      seller_name: "Firma Sp. z o.o.",
      buyer_nip: "0987654321",
      buyer_name: "Acme Corp",
      invoice_number: "FV/2024/001",
      issue_date: "2024-01-15",
      net_amount: "1000.00",
      vat_amount: "230.00",
      gross_amount: "1230.00",
      currency: "PLN",
      status: "pending",
      source: "ksef",
      duplicate_of_id: nil,
      duplicate_status: nil,
      ksef_acquisition_date: "2024-01-15T10:30:00Z",
      permanent_storage_date: "2024-01-16T00:00:00Z",
      inserted_at: "2024-01-15T10:35:00Z",
      updated_at: "2024-01-15T10:35:00Z"
    }
  })
end
