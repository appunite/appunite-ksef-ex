defmodule KsefHubWeb.Api.TokenController do
  use KsefHubWeb, :controller

  import KsefHubWeb.ChangesetHelpers

  alias KsefHub.Accounts

  def index(conn, _params) do
    user_id = conn.assigns.api_token.created_by_id
    tokens = Accounts.list_api_tokens(user_id)
    json(conn, %{data: Enum.map(tokens, &token_json/1)})
  end

  def create(conn, params) do
    user_id = conn.assigns.api_token.created_by_id

    attrs = %{
      name: params["name"],
      description: params["description"],
      expires_at: params["expires_at"]
    }

    case Accounts.create_api_token(user_id, attrs) do
      {:ok, %{token: plain_token, api_token: api_token}} ->
        conn
        |> put_status(:created)
        |> json(%{
          data: Map.put(token_json(api_token), :token, plain_token),
          message: "Store this token securely — it will not be shown again."
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})
    end
  end

  def delete(conn, %{"id" => id}) do
    user_id = conn.assigns.api_token.created_by_id

    case Accounts.revoke_api_token(user_id, id) do
      {:ok, _token} ->
        json(conn, %{message: "Token revoked successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Token not found"})
    end
  end

  defp token_json(token) do
    %{
      id: token.id,
      name: token.name,
      description: token.description,
      token_prefix: token.token_prefix,
      last_used_at: token.last_used_at,
      request_count: token.request_count,
      is_active: token.is_active,
      inserted_at: token.inserted_at
    }
  end
end
