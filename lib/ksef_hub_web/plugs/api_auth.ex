defmodule KsefHubWeb.Plugs.ApiAuth do
  @moduledoc """
  Plug that validates Bearer API tokens for JSON API routes.

  On success, assigns both `:api_token` and `:current_company` to the conn.
  The company is derived from the token — API consumers never need to pass
  a company_id parameter.
  """

  import Plug.Conn
  import Phoenix.Controller
  import KsefHubWeb.AuthHelpers, only: [resolve_role: 2]

  alias KsefHub.Accounts

  @doc false
  @spec init(Keyword.t()) :: Keyword.t()
  def init(opts), do: opts

  @doc false
  @spec call(Plug.Conn.t(), Keyword.t()) :: Plug.Conn.t()
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, api_token} <- Accounts.validate_api_token(token) do
      Accounts.track_token_usage(api_token.id)
      role = resolve_role(api_token.created_by_id, api_token.company_id)

      conn
      |> assign(:api_token, api_token)
      |> assign(:current_company, api_token.company)
      |> assign(:current_role, role)
    else
      {:error, :expired} ->
        conn
        |> put_resp_header("www-authenticate", "Bearer")
        |> put_status(:unauthorized)
        |> json(%{error: "API token has expired"})
        |> halt()

      _ ->
        conn
        |> put_resp_header("www-authenticate", "Bearer")
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid or missing API token"})
        |> halt()
    end
  end
end
