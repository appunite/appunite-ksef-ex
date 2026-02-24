defmodule KsefHubWeb.LiveAuth do
  @moduledoc """
  LiveView on_mount hook that loads the current user and company into socket assigns.
  Redirects unauthenticated users to the home page.
  Redirects users with no companies to the company creation page.
  Assigns `:current_role` from the user's membership for the current company.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  import KsefHubWeb.AuthHelpers, only: [resolve_role: 2]

  alias KsefHub.Accounts
  alias KsefHub.Companies
  alias KsefHub.Companies.Company

  @doc """
  Assigns `:current_user`, `:current_company`, `:companies`, and `:current_role` to the socket.
  """
  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, session, socket) do
    user_token = session["user_token"]

    if is_binary(user_token) do
      case Accounts.get_user_by_session_token(user_token) do
        %{} = user ->
          socket
          |> assign_user_and_companies(user, session)
          |> maybe_redirect_for_company()

        nil ->
          {:halt,
           socket
           |> put_flash(:error, "Session expired. Please log in again.")
           |> redirect(to: "/")}
      end
    else
      {:halt,
       socket
       |> put_flash(:error, "You must be logged in to access this page.")
       |> redirect(to: "/")}
    end
  end

  def on_mount(:require_owner, _params, _session, socket) do
    if socket.assigns[:current_role] == :owner do
      {:cont, socket}
    else
      {:halt,
       socket
       |> put_flash(:error, "Only the owner can manage the team.")
       |> redirect(to: "/dashboard")}
    end
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    user_token = session["user_token"]

    if is_binary(user_token) && Accounts.get_user_by_session_token(user_token) do
      {:halt, redirect(socket, to: "/dashboard")}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    user_token = session["user_token"]

    user =
      if is_binary(user_token),
        do: Accounts.get_user_by_session_token(user_token),
        else: nil

    {:cont, assign(socket, :current_user, user)}
  end

  @spec assign_user_and_companies(Phoenix.LiveView.Socket.t(), map(), map()) ::
          Phoenix.LiveView.Socket.t()
  defp assign_user_and_companies(socket, user, session) do
    companies = Companies.list_companies_for_user(user.id)
    resolved = resolve_company(companies, session["current_company_id"])
    current_company = resolved || List.first(companies)
    current_role = resolve_role(user.id, current_company && current_company.id)

    socket
    |> assign(:current_user, user)
    |> assign(:companies, companies)
    |> assign(:current_company, current_company)
    |> assign(:current_role, current_role)
    |> assign(:current_path, nil)
    |> attach_hook(:set_current_path, :handle_params, fn _params, uri, socket ->
      {:cont, assign(socket, :current_path, URI.parse(uri).path)}
    end)
  end

  @spec maybe_redirect_for_company(Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  defp maybe_redirect_for_company(socket) do
    if socket.assigns.companies == [] && !company_route?(socket) do
      {:halt, redirect(socket, to: "/companies/new")}
    else
      {:cont, socket}
    end
  end

  @spec resolve_company([Company.t()], Ecto.UUID.t() | nil) :: Company.t() | nil
  defp resolve_company([], _), do: nil
  defp resolve_company(_companies, nil), do: nil

  defp resolve_company(companies, company_id) do
    Enum.find(companies, fn c -> c.id == company_id end)
  end

  @spec company_route?(Phoenix.LiveView.Socket.t()) :: boolean()
  defp company_route?(socket) do
    socket.view in [KsefHubWeb.CompanyLive.Index]
  end
end
