defmodule KsefHubWeb.LiveAuth do
  @moduledoc """
  LiveView on_mount hook that loads the current user and company into socket assigns.
  Redirects unauthenticated users to the home page.
  Redirects users with no companies to the company creation page.
  Assigns `:current_role` from the user's membership for the current company.

  The company context is resolved from the URL `company_id` param (for company-scoped
  routes under `/c/:company_id/...`), falling back to the session, then the user's
  first company.
  """

  use KsefHubWeb, :verified_routes

  import Phoenix.LiveView
  import Phoenix.Component

  import KsefHubWeb.AuthHelpers, only: [resolve_role: 2]
  import KsefHubWeb.UrlHelpers, only: [default_path: 1]

  alias KsefHub.Accounts
  alias KsefHub.Companies

  @doc """
  Assigns `:current_user`, `:current_company`, `:companies`, and `:current_role` to the socket.
  """
  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, params, session, socket) do
    case fetch_user_from_session(session) do
      {:ok, user} ->
        case assign_user_and_companies(socket, user, params, session) do
          {:halt, _} = halt -> halt
          socket -> maybe_redirect_for_company(socket)
        end

      :error ->
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
       |> redirect(to: default_path(socket.assigns[:current_company]))}
    end
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    case fetch_user_from_session(session) do
      {:ok, user} ->
        company = user.id |> Companies.list_companies_for_user() |> List.first()
        {:halt, redirect(socket, to: default_path(company))}

      :error ->
        {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    user =
      case fetch_user_from_session(session) do
        {:ok, user} -> user
        :error -> nil
      end

    {:cont, assign(socket, :current_user, user)}
  end

  @spec assign_user_and_companies(Phoenix.LiveView.Socket.t(), map(), map(), map()) ::
          Phoenix.LiveView.Socket.t() | {:halt, Phoenix.LiveView.Socket.t()}
  defp assign_user_and_companies(socket, user, params, session) do
    companies = Companies.list_companies_for_user(user.id)
    url_company_id = params["company_id"]

    case resolve_current_company(companies, url_company_id, session) do
      {:error, :unauthorized} ->
        {:halt,
         socket
         |> assign(:current_user, user)
         |> put_flash(:error, "You don't have access to this company.")
         |> redirect(to: ~p"/companies")}

      current_company ->
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
  end

  @spec resolve_current_company([Companies.Company.t()], String.t() | nil, map()) ::
          Companies.Company.t() | nil | {:error, :unauthorized}
  defp resolve_current_company(companies, url_company_id, _session)
       when is_binary(url_company_id) do
    case find_company(companies, url_company_id) do
      nil -> {:error, :unauthorized}
      company -> company
    end
  end

  defp resolve_current_company(companies, _nil, session) do
    find_company(companies, session["current_company_id"]) || List.first(companies)
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

  @spec fetch_user_from_session(map()) :: {:ok, map()} | :error
  defp fetch_user_from_session(session) do
    with token when is_binary(token) <- session["user_token"],
         %{} = user <- Accounts.get_user_by_session_token(token) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  @spec find_company([Companies.Company.t()], String.t() | nil) :: Companies.Company.t() | nil
  defp find_company(_companies, nil), do: nil
  defp find_company(companies, id), do: Enum.find(companies, &(&1.id == id))

  @spec company_route?(Phoenix.LiveView.Socket.t()) :: boolean()
  defp company_route?(socket) do
    socket.view in [KsefHubWeb.CompanyLive.Index]
  end
end
