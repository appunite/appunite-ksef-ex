defmodule KsefHubWeb.Api.TokenController do
  use KsefHubWeb, :controller

  alias KsefHub.Accounts

  def index(conn, _params) do
    tokens = Accounts.list_api_tokens()
    json(conn, %{data: Enum.map(tokens, &token_json/1)})
  end

  def create(conn, %{"name" => name} = params) do
    attrs = %{
      name: name,
      description: params["description"]
    }

    case Accounts.create_api_token(attrs) do
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
    case Accounts.revoke_api_token(id) do
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

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
