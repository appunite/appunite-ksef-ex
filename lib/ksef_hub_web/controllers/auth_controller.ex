defmodule KsefHubWeb.AuthController do
  use KsefHubWeb, :controller

  plug Ueberauth

  alias KsefHub.Accounts

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    email = auth.info.email

    if is_binary(email) and email != "" and Accounts.allowed_email?(email) do
      user_info = %{
        uid: auth.uid,
        email: email,
        name: auth.info.name,
        avatar_url: auth.info.image
      }

      case Accounts.find_or_create_user(user_info) do
        {:ok, user} ->
          conn
          |> configure_session(renew: true)
          |> put_session(:user_id, user.id)
          |> put_flash(:info, "Welcome, #{user.name || user.email}!")
          |> redirect(to: ~p"/")

        {:error, _reason} ->
          conn
          |> put_flash(:error, "Authentication failed.")
          |> redirect(to: ~p"/")
      end
    else
      conn
      |> put_flash(:error, "Your email is not authorized to access this application.")
      |> redirect(to: ~p"/")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed.")
    |> redirect(to: ~p"/")
  end

  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Logged out successfully.")
    |> redirect(to: ~p"/")
  end
end
