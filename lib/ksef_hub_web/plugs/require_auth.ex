defmodule KsefHubWeb.Plugs.RequireAuth do
  @moduledoc """
  Plug that requires a logged-in user via session token.
  Redirects to home page if not authenticated.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias KsefHub.Accounts

  @doc false
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc false
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    user_token = get_session(conn, :user_token)

    cond do
      conn.assigns[:current_user] ->
        conn

      is_binary(user_token) ->
        case Accounts.get_user_by_session_token(user_token) do
          nil ->
            conn
            |> configure_session(drop: true)
            |> put_flash(:error, "Session expired. Please log in again.")
            |> redirect(to: "/")
            |> halt()

          user ->
            assign(conn, :current_user, user)
        end

      true ->
        conn
        |> put_flash(:error, "You must be logged in to access this page.")
        |> redirect(to: "/")
        |> halt()
    end
  end
end
