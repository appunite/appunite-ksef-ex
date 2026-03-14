defmodule KsefHubWeb.Api.PaymentRequestController do
  @moduledoc """
  REST API controller for payment request operations.

  All actions are scoped to the company associated with the authenticated API token.
  """

  use KsefHubWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import KsefHubWeb.ChangesetHelpers
  import KsefHubWeb.JsonHelpers, only: [atomize_keys: 2]

  alias KsefHub.PaymentRequests
  alias KsefHub.PaymentRequests.PaymentRequest
  alias KsefHubWeb.Schemas
  alias OpenApiSpex.Schema

  plug KsefHubWeb.Plugs.RequirePermission,
       :view_payment_requests when action in [:index]

  plug KsefHubWeb.Plugs.RequirePermission,
       :manage_payment_requests when action in [:create, :mark_paid]

  @create_allowed_keys ~w(recipient_name amount currency title iban note invoice_id
    recipient_address)

  tags(["Payment Requests"])
  security([%{"bearer" => []}])

  operation(:index,
    summary: "List payment requests",
    description: "Returns a paginated list of payment requests for the company.",
    parameters: [
      status: [
        in: :query,
        description: "Filter by status.",
        schema: %Schema{type: :string, enum: ["pending", "paid"]}
      ],
      query: [
        in: :query,
        description: "Search recipient, title, or IBAN.",
        schema: %Schema{type: :string}
      ],
      date_from: [
        in: :query,
        description: "Filter by created date (from, ISO 8601).",
        schema: %Schema{type: :string, format: :date}
      ],
      date_to: [
        in: :query,
        description: "Filter by created date (to, ISO 8601).",
        schema: %Schema{type: :string, format: :date}
      ],
      page: [
        in: :query,
        description: "Page number (1-based, default 1).",
        schema: %Schema{type: :integer, minimum: 1, default: 1}
      ],
      per_page: [
        in: :query,
        description: "Results per page (default 25, max 100).",
        schema: %Schema{type: :integer, minimum: 1, maximum: 100, default: 25}
      ]
    ],
    responses: %{
      200 => {"Paginated list", "application/json", Schemas.PaymentRequestListResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Lists payment requests with optional filters and pagination."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    company_id = conn.assigns.current_company.id
    filters = build_filters(params)
    result = PaymentRequests.list_payment_requests_paginated(company_id, filters)

    json(conn, %{
      data: Enum.map(result.entries, &payment_request_json/1),
      meta: %{
        page: result.page,
        per_page: result.per_page,
        total_count: result.total_count,
        total_pages: result.total_pages
      }
    })
  end

  operation(:create,
    summary: "Create payment request",
    description: "Creates a new payment request.",
    request_body:
      {"Payment request attrs", "application/json", Schemas.CreatePaymentRequestRequest},
    responses: %{
      201 => {"Created", "application/json", Schemas.PaymentRequestResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden", "application/json", Schemas.ErrorResponse},
      422 => {"Validation error", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Creates a payment request."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    company_id = conn.assigns.current_company.id
    user_id = conn.assigns.api_token.created_by_id
    attrs = atomize_keys(params, @create_allowed_keys)

    case PaymentRequests.create_payment_request(company_id, user_id, attrs) do
      {:ok, pr} ->
        conn
        |> put_status(:created)
        |> json(%{data: payment_request_json(pr)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})
    end
  end

  operation(:mark_paid,
    summary: "Mark payment request as paid",
    description: "Marks a single payment request as paid.",
    parameters: [
      id: [
        in: :path,
        description: "Payment Request UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Success", "application/json", Schemas.PaymentRequestResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Marks a payment request as paid."
  @spec mark_paid(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def mark_paid(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id

    case PaymentRequests.mark_as_paid(company_id, id) do
      {:ok, pr} ->
        json(conn, %{data: payment_request_json(pr)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Payment request not found"})
    end
  end

  # --- Private ---

  @spec build_filters(map()) :: map()
  defp build_filters(params) do
    %{}
    |> maybe_put_enum(:status, params["status"])
    |> maybe_put(:query, params["query"])
    |> maybe_put_date(:date_from, params["date_from"])
    |> maybe_put_date(:date_to, params["date_to"])
    |> maybe_put_integer(:page, params["page"])
    |> maybe_put_integer(:per_page, params["per_page"])
  end

  @spec maybe_put(map(), atom(), term()) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec maybe_put_enum(map(), atom(), String.t() | nil) :: map()
  defp maybe_put_enum(map, _key, nil), do: map
  defp maybe_put_enum(map, _key, ""), do: map

  defp maybe_put_enum(map, key, value) do
    type = PaymentRequest.__schema__(:type, key)

    case Ecto.Type.cast(type, value) do
      {:ok, atom} -> Map.put(map, key, atom)
      :error -> map
    end
  end

  @spec maybe_put_date(map(), atom(), String.t() | nil) :: map()
  defp maybe_put_date(map, _key, nil), do: map
  defp maybe_put_date(map, _key, ""), do: map

  defp maybe_put_date(map, key, value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> Map.put(map, key, date)
      _ -> map
    end
  end

  @spec maybe_put_integer(map(), atom(), String.t() | nil) :: map()
  defp maybe_put_integer(map, _key, nil), do: map
  defp maybe_put_integer(map, _key, ""), do: map

  defp maybe_put_integer(map, key, value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> Map.put(map, key, int)
      _ -> map
    end
  end

  defp maybe_put_integer(map, key, value) when is_integer(value) and value > 0 do
    Map.put(map, key, value)
  end

  defp maybe_put_integer(map, _key, _value), do: map

  @spec payment_request_json(PaymentRequest.t()) :: map()
  defp payment_request_json(pr) do
    %{
      id: pr.id,
      recipient_name: pr.recipient_name,
      recipient_address: pr.recipient_address,
      amount: pr.amount && Decimal.to_string(pr.amount),
      currency: pr.currency,
      title: pr.title,
      iban: pr.iban,
      note: pr.note,
      status: pr.status,
      invoice_id: pr.invoice_id,
      inserted_at: pr.inserted_at,
      updated_at: pr.updated_at
    }
  end
end
