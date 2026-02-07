defmodule KsefHubWeb.Plugs.RequireAuth do
  @moduledoc """
  Plug that requires a logged-in user via session.
  Redirects to home page if not authenticated.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias KsefHub.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :user_id) do
      nil ->
        conn
        |> put_flash(:error, "You must be logged in to access this page.")
        |> redirect(to: "/")
        |> halt()

      user_id ->
        try do
          user = Accounts.get_user!(user_id)
          assign(conn, :current_user, user)
        rescue
          _e in [Ecto.NoResultsError, Ecto.Query.CastError] ->
            conn
            |> configure_session(drop: true)
            |> put_flash(:error, "Session expired. Please log in again.")
            |> redirect(to: "/")
            |> halt()
        end
    end
  end
end
