defmodule KsefHubWeb.Schemas.Responses do
  @moduledoc """
  OpenAPI response wrapper schemas for the KSeF Hub API.
  """

  alias OpenApiSpex.Schema

  defmodule InvoiceResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "InvoiceResponse",
      description: "Single invoice response.",
      type: :object,
      properties: %{
        data: KsefHubWeb.Schemas.Invoice
      },
      required: [:data]
    })
  end

  defmodule InvoiceListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "InvoiceListResponse",
      description: "List of invoices response.",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: KsefHubWeb.Schemas.Invoice}
      },
      required: [:data]
    })
  end

  defmodule TokenResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "TokenResponse",
      description: "Single token response.",
      type: :object,
      properties: %{
        data: KsefHubWeb.Schemas.Token
      },
      required: [:data]
    })
  end

  defmodule TokenCreatedResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "TokenCreatedResponse",
      description:
        "Response after creating a new token. Contains the plain token shown only once.",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          allOf: [
            KsefHubWeb.Schemas.Token,
            %Schema{
              type: :object,
              properties: %{
                token: %Schema{
                  type: :string,
                  description: "Full token value. Shown only once at creation."
                }
              },
              required: [:token]
            }
          ]
        },
        message: %Schema{type: :string}
      },
      required: [:data, :message]
    })
  end

  defmodule TokenListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "TokenListResponse",
      description: "List of API tokens response.",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: KsefHubWeb.Schemas.Token}
      },
      required: [:data]
    })
  end

  defmodule MessageResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "MessageResponse",
      description: "Simple message response.",
      type: :object,
      properties: %{
        message: %Schema{type: :string}
      },
      required: [:message]
    })
  end

  defmodule ErrorResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ErrorResponse",
      description: "Error response.",
      type: :object,
      properties: %{
        error: %Schema{
          oneOf: [
            %Schema{type: :string, description: "Error message."},
            %Schema{type: :object, description: "Field-level validation errors."}
          ]
        }
      },
      required: [:error]
    })
  end
end
