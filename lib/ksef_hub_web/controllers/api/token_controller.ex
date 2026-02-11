defmodule KsefHubWeb.Api.TokenController do
  @moduledoc """
  REST API controller for token management.

  All actions are scoped to the company associated with the authenticated API token.
  Only company owners can create and revoke tokens.
  """

  use KsefHubWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import KsefHubWeb.ChangesetHelpers

  alias KsefHub.Accounts
  alias KsefHubWeb.Schemas
  alias OpenApiSpex.Schema

  tags(["Tokens"])
  security([%{"bearer" => []}])

  operation(:index,
    summary: "List API tokens",
    description:
      "Returns all API tokens belonging to the authenticated user for the token's company.",
    responses: %{
      200 => {"Token list", "application/json", Schemas.TokenListResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse}
    }
  )

  def index(conn, _params) do
    user_id = conn.assigns.api_token.created_by_id
    company_id = conn.assigns.current_company.id
    tokens = Accounts.list_api_tokens(user_id, company_id)
    json(conn, %{data: Enum.map(tokens, &token_json/1)})
  end

  operation(:create,
    summary: "Create API token",
    description:
      "Creates a new API token scoped to the token's company. The full token value is returned only once.",
    request_body:
      {"Token params", "application/json",
       %Schema{
         type: :object,
         properties: %{
           name: %Schema{type: :string, description: "Human-readable token name."},
           description: %Schema{type: :string, nullable: true},
           expires_at: %Schema{
             type: :string,
             format: :"date-time",
             nullable: true,
             description: "Optional expiration timestamp. Null means no expiry."
           }
         },
         required: [:name]
       }},
    responses: %{
      201 => {"Created token", "application/json", Schemas.TokenCreatedResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden", "application/json", Schemas.ErrorResponse},
      422 => {"Validation error", "application/json", Schemas.ErrorResponse}
    }
  )

  def create(conn, params) do
    user_id = conn.assigns.api_token.created_by_id
    company_id = conn.assigns.current_company.id

    attrs = %{
      name: params["name"],
      description: params["description"],
      expires_at: params["expires_at"]
    }

    case Accounts.create_api_token(user_id, company_id, attrs) do
      {:ok, %{token: plain_token, api_token: api_token}} ->
        conn
        |> put_status(:created)
        |> json(%{
          data: Map.put(token_json(api_token), :token, plain_token),
          message: "Store this token securely — it will not be shown again."
        })

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only company owners can create API tokens"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})
    end
  end

  operation(:delete,
    summary: "Revoke API token",
    description: "Permanently revokes an API token. This cannot be undone.",
    parameters: [
      id: [
        in: :path,
        description: "Token UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Token revoked", "application/json", Schemas.MessageResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse}
    }
  )

  def delete(conn, %{"id" => id}) do
    user_id = conn.assigns.api_token.created_by_id
    company_id = conn.assigns.current_company.id

    case Accounts.revoke_api_token(user_id, company_id, id) do
      {:ok, _token} ->
        json(conn, %{message: "Token revoked successfully"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only company owners can revoke API tokens"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Token not found"})
    end
  end

  @spec token_json(Accounts.ApiToken.t()) :: map()
  defp token_json(token) do
    %{
      id: token.id,
      name: token.name,
      description: token.description,
      token_prefix: token.token_prefix,
      expires_at: token.expires_at,
      last_used_at: token.last_used_at,
      request_count: token.request_count,
      is_active: token.is_active,
      inserted_at: token.inserted_at
    }
  end
end
