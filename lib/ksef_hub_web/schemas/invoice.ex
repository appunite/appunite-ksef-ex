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
        nullable: true,
        description: "Seller 10-digit NIP. May be null for partial pdf_upload extractions."
      },
      seller_name: %Schema{type: :string, nullable: true},
      buyer_nip: %Schema{
        type: :string,
        pattern: "^\\d{10}$",
        nullable: true,
        description: "Buyer 10-digit NIP."
      },
      buyer_name: %Schema{type: :string, nullable: true},
      invoice_number: %Schema{
        type: :string,
        nullable: true,
        description: "Sequential invoice number."
      },
      issue_date: %Schema{type: :string, format: :date, nullable: true},
      net_amount: %Schema{type: :string, nullable: true, description: "Decimal as string."},
      gross_amount: %Schema{type: :string, nullable: true, description: "Decimal as string."},
      currency: %Schema{
        type: :string,
        nullable: true,
        description: "ISO 4217 currency code.",
        example: "PLN"
      },
      status: %Schema{type: :string, enum: ["pending", "approved", "rejected"]},
      source: %Schema{
        type: :string,
        enum: ["ksef", "manual", "pdf_upload"],
        description: "Invoice origin: synced from KSeF, manually created, or uploaded as PDF."
      },
      extraction_status: %Schema{
        type: :string,
        enum: ["complete", "partial", "failed"],
        nullable: true,
        description:
          "PDF extraction quality. Only set for pdf_upload source. complete=all fields extracted, partial=some fields missing, failed=extraction error."
      },
      original_filename: %Schema{
        type: :string,
        nullable: true,
        description: "Original filename of the uploaded PDF."
      },
      purchase_order: %Schema{
        type: :string,
        nullable: true,
        maxLength: 256,
        description:
          "Purchase order identifier. Extracted from KSeF XML (NrZamowienia or DodatkowyOpis) or PDF extraction."
      },
      sales_date: %Schema{
        type: :string,
        format: :date,
        nullable: true,
        description: "Sales/delivery date (P_6 from FA(3) XML or PDF extraction)."
      },
      due_date: %Schema{
        type: :string,
        format: :date,
        nullable: true,
        description: "Payment due date. PDF-only (not in FA(3) spec)."
      },
      billing_date: %Schema{
        type: :string,
        format: :date,
        nullable: true,
        pattern: "^\\d{4}-\\d{2}-01$",
        description:
          "Accounting period date (first day of month, YYYY-MM-01). Auto-computed from sales_date or issue_date, but user-overridable. Used for grouping invoices into billing periods."
      },
      iban: %Schema{
        type: :string,
        nullable: true,
        maxLength: 34,
        description:
          "Seller's bank account number (IBAN). From KSeF Rachunek/NrRB or PDF extraction."
      },
      seller_address: %Schema{
        type: :object,
        nullable: true,
        description: "Seller address extracted from KSeF XML or PDF.",
        properties: %{
          street: %Schema{type: :string, nullable: true},
          city: %Schema{type: :string, nullable: true},
          postal_code: %Schema{type: :string, nullable: true},
          country: %Schema{type: :string, nullable: true}
        }
      },
      buyer_address: %Schema{
        type: :object,
        nullable: true,
        description: "Buyer address extracted from KSeF XML or PDF.",
        properties: %{
          street: %Schema{type: :string, nullable: true},
          city: %Schema{type: :string, nullable: true},
          postal_code: %Schema{type: :string, nullable: true},
          country: %Schema{type: :string, nullable: true}
        }
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
      prediction_status: %Schema{
        type: :string,
        enum: ["pending", "predicted", "needs_review", "manual"],
        nullable: true,
        description:
          "ML prediction status. nil=not applicable, pending=awaiting, predicted=auto-applied (>=80%), needs_review=stored but not applied (<80%), manual=user overrode."
      },
      prediction_category_name: %Schema{
        type: :string,
        nullable: true,
        description: "Category name predicted by the ML model."
      },
      prediction_tag_name: %Schema{
        type: :string,
        nullable: true,
        description: "Tag name predicted by the ML model."
      },
      prediction_category_confidence: %Schema{
        type: :number,
        format: :float,
        nullable: true,
        description: "Confidence score (0.0-1.0) for the predicted category."
      },
      prediction_tag_confidence: %Schema{
        type: :number,
        format: :float,
        nullable: true,
        description: "Confidence score (0.0-1.0) for the predicted tag."
      },
      prediction_model_version: %Schema{
        type: :string,
        nullable: true,
        description: "Version of the ML model that generated the prediction."
      },
      prediction_predicted_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "When the ML prediction was generated."
      },
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :type, :status],
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
      gross_amount: "1230.00",
      currency: "PLN",
      status: "pending",
      source: "ksef",
      category_id: "d4c3b2a1-9876-5432-fedc-ba0987654321",
      category: %{
        id: "d4c3b2a1-9876-5432-fedc-ba0987654321",
        name: "finance:invoices",
        emoji: "💰",
        description: "Financial invoices",
        sort_order: 0
      },
      tags: [
        %{id: "e5d4c3b2-a198-7654-3210-fedcba098765", name: "urgent", usage_count: 3},
        %{id: "f6e5d4c3-b2a1-9876-5432-10fedcba0987", name: "quarterly", usage_count: 7}
      ],
      duplicate_of_id: nil,
      duplicate_status: nil,
      ksef_acquisition_date: "2024-01-15T10:30:00Z",
      permanent_storage_date: "2024-01-16T00:00:00Z",
      inserted_at: "2024-01-15T10:35:00Z",
      updated_at: "2024-01-15T10:35:00Z"
    },
    "x-pdf-upload-example": %{
      id: "b2c3d4e5-f6a7-8901-bcde-f12345678901",
      type: "expense",
      source: "pdf_upload",
      status: "pending",
      extraction_status: "partial",
      original_filename: "invoice_february.pdf",
      seller_nip: "1234567890",
      seller_name: "Dostawca Sp. z o.o.",
      buyer_nip: nil,
      buyer_name: nil,
      invoice_number: "FV/2026/042",
      issue_date: "2026-02-20",
      net_amount: "5000.00",
      gross_amount: "6150.00",
      currency: "PLN",
      inserted_at: "2026-02-20T14:30:00Z",
      updated_at: "2026-02-20T14:30:00Z"
    }
  })
end
