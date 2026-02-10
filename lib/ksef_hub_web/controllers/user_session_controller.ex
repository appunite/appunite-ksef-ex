defmodule KsefHubWeb.UserSessionController do
  @moduledoc """
  Handles email/password login form submission and logout.

  Login is initiated by a LiveView that validates the form, then triggers
  a real HTTP POST via `phx-trigger-action` to create the session.
  """

  use KsefHubWeb, :controller

  alias KsefHub.Accounts
  alias KsefHubWeb.UserAuth

  @doc """
  Creates a new session from email/password credentials.

  Called via `phx-trigger-action` from UserLoginLive.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, "Welcome back!")
      |> UserAuth.log_in_user(user, %{return_to: user_params["return_to"]})
    else
      conn
      |> put_flash(:error, "Invalid email or password.")
      |> redirect(to: ~p"/users/log-in")
    end
  end

  @doc """
  Logs the user out.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
