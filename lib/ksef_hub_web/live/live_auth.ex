defmodule KsefHubWeb.LiveAuth do
  @moduledoc """
  LiveView on_mount hook that loads the current user and company into socket assigns.
  Redirects unauthenticated users to the home page.
  Redirects users with no companies to the company creation page.
  Assigns `:current_role` from the user's membership for the current company.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias KsefHub.Accounts
  alias KsefHub.Companies

  @doc """
  Assigns `:current_user`, `:current_company`, `:companies`, and `:current_role` to the socket.
  """
  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, session, socket) do
    with raw_id when is_binary(raw_id) <- session["user_id"],
         {:ok, _} <- Ecto.UUID.cast(raw_id),
         %{} = user <- Accounts.get_user(raw_id) do
      socket
      |> assign_user_and_companies(user, session)
      |> maybe_redirect_for_company()
    else
      _ ->
        socket =
          socket
          |> put_flash(:error, "You must be logged in to access this page.")
          |> redirect(to: "/")

        {:halt, socket}
    end
  end

  @spec assign_user_and_companies(Phoenix.LiveView.Socket.t(), map(), map()) ::
          Phoenix.LiveView.Socket.t()
  defp assign_user_and_companies(socket, user, session) do
    companies = Companies.list_companies_for_user(user.id)
    resolved = resolve_company(companies, session["current_company_id"])
    current_company = resolved || List.first(companies)
    current_role = resolve_role(user.id, current_company)

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

  @spec resolve_role(Ecto.UUID.t(), map() | nil) :: String.t() | nil
  defp resolve_role(_user_id, nil), do: nil

  defp resolve_role(user_id, company) do
    case Companies.get_membership(user_id, company.id) do
      %{role: role} -> role
      nil -> nil
    end
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

  @spec resolve_company([map()], Ecto.UUID.t() | nil) :: map() | nil
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
