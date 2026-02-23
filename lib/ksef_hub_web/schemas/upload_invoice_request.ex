defmodule KsefHubWeb.Schemas.UploadInvoiceRequest do
  @moduledoc """
  OpenAPI schema for the PDF invoice upload request.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "UploadInvoiceRequest",
    description: "Multipart request for uploading a PDF invoice.",
    type: :object,
    properties: %{
      file: %Schema{
        type: :string,
        format: :binary,
        description: "PDF file to upload (max 10MB)."
      },
      type: %Schema{
        type: :string,
        enum: ["income", "expense"],
        description: "Invoice type."
      }
    },
    required: [:file, :type]
  })
end
