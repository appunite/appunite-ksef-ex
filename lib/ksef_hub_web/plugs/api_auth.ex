defmodule KsefHubWeb.Plugs.ApiAuth do
  @moduledoc """
  Plug that validates Bearer API tokens for JSON API routes.
  Tracks token usage on successful authentication.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias KsefHub.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, api_token} <- Accounts.validate_api_token(token) do
      Accounts.track_token_usage(api_token.id)
      assign(conn, :api_token, api_token)
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
