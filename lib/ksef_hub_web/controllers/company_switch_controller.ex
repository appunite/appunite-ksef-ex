defmodule KsefHubWeb.CompanySwitchController do
  @moduledoc """
  Controller for switching the current company context.
  Verifies the user has a membership for the target company,
  stores the selected company_id in the session, and redirects back.

  When the return_to path contains a `/c/:company_id/...` segment,
  the company_id is rewritten to the new company.
  """

  use KsefHubWeb, :controller

  alias KsefHub.Accounts.User
  alias KsefHub.Companies

  @doc "Switches the current company context and redirects."
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"id" => id} = params) do
    case conn.assigns[:current_user] do
      %User{} = user ->
        with {:ok, uuid} <- Ecto.UUID.cast(id),
             %{} <- Companies.get_membership(user.id, uuid) do
          conn
          |> put_session(:current_company_id, uuid)
          |> redirect(to: safe_return_to(params["return_to"], uuid))
        else
          _ ->
            conn
            |> put_flash(:error, "Company not found.")
            |> redirect(to: ~p"/companies")
        end

      _ ->
        conn
        |> put_flash(:error, "You must be logged in.")
        |> redirect(to: ~p"/")
    end
  end

  @spec safe_return_to(String.t() | nil, String.t()) :: String.t()
  defp safe_return_to(nil, company_id), do: ~p"/c/#{company_id}/invoices"

  defp safe_return_to(path, company_id) do
    uri = URI.parse(path)

    if uri.host == nil && uri.scheme == nil && String.starts_with?(path, "/") &&
         !String.starts_with?(path, "//") do
      rewrite_company_in_path(path, company_id)
    else
      ~p"/c/#{company_id}/invoices"
    end
  end

  @spec rewrite_company_in_path(String.t(), String.t()) :: String.t()
  defp rewrite_company_in_path("/c/" <> _ = path, new_company_id) do
    Regex.replace(~r{^/c/[^/]+}, path, "/c/#{new_company_id}")
  end

  defp rewrite_company_in_path(_path, new_company_id) do
    ~p"/c/#{new_company_id}/invoices"
  end
end
