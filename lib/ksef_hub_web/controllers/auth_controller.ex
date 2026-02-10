defmodule KsefHubWeb.AuthController do
  @moduledoc """
  Handles OAuth authentication via Ueberauth (Google Sign-In).

  Validates that the email is verified by the provider before creating
  or finding the user. Any verified Google user can sign in.
  """

  use KsefHubWeb, :controller

  plug Ueberauth

  alias KsefHub.Accounts
  alias KsefHub.Invitations
  alias KsefHubWeb.UserAuth

  @doc """
  Handles the OAuth callback. Rejects unverified emails and blank/nil emails.
  Uses `get_or_create_google_user/1` which links Google accounts to existing
  email-registered users.
  """
  @spec callback(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    email = auth.info.email

    email_verified =
      get_in(auth, [Access.key(:extra), Access.key(:raw_info), :user, "email_verified"])

    if is_binary(email) and email != "" and email_verified == true do
      user_info = %{
        uid: auth.uid,
        email: email,
        name: auth.info.name,
        avatar_url: auth.info.image
      }

      case Accounts.get_or_create_google_user(user_info) do
        {:ok, user} ->
          Invitations.accept_pending_invitations_for_email(user)

          conn
          |> put_flash(:info, "Welcome, #{user.name || user.email}!")
          |> UserAuth.log_in_user(user)

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
end
