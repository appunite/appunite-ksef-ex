defmodule KsefHubWeb.UserAuth do
  @moduledoc """
  Helpers for authenticating users via session tokens.

  Provides `log_in_user/3` and `log_out_user/1` for use in controllers
  and plugs.
  """

  use KsefHubWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias KsefHub.Accounts
  alias KsefHub.ActivityLog.Events
  alias KsefHub.Companies

  import KsefHubWeb.UrlHelpers, only: [default_path: 1, sanitize_return_to: 1]

  @doc """
  Logs the user in by generating a session token, renewing the session,
  and redirecting to the appropriate path.
  """
  @spec log_in_user(Plug.Conn.t(), KsefHub.Accounts.User.t(), map()) :: Plug.Conn.t()
  def log_in_user(conn, user, params \\ %{}) do
    token = Accounts.generate_user_session_token(user)
    return_to = sanitize_return_to(params[:return_to] || params["return_to"])

    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    Events.user_logged_in(user, ip_address: ip)

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
    |> redirect(to: return_to || signed_in_path(user))
  end

  @doc """
  Logs the user out by deleting the session token from the database,
  clearing the session, and redirecting to home.
  """
  @spec log_out_user(Plug.Conn.t()) :: Plug.Conn.t()
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user = conn.assigns[:current_user]

    if live_socket_id = get_session(conn, :live_socket_id) do
      KsefHubWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    user_token && Accounts.delete_user_session_token(user_token)

    if user do
      ip = conn.remote_ip |> :inet.ntoa() |> to_string()
      Events.user_logged_out(user, ip_address: ip)
    end

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> redirect(to: ~p"/")
  end

  @doc """
  Returns the path to redirect to after login.

  Resolves the user's first company and returns a company-scoped path.
  Falls back to `/companies` if the user has no companies.
  """
  @spec signed_in_path(KsefHub.Accounts.User.t()) :: String.t()
  def signed_in_path(user) do
    user.id
    |> Companies.list_companies_for_user()
    |> List.first()
    |> default_path()
  end
end
