defmodule KsefHubWeb.LiveAuth do
  @moduledoc """
  LiveView on_mount hook that loads the current user and company into socket assigns.
  Redirects unauthenticated users to the home page.
  Redirects users with no companies to the company creation page.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias KsefHub.Accounts
  alias KsefHub.Companies

  @doc """
  Assigns `:current_user`, `:current_company`, and `:companies` to the socket.
  """
  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, session, socket) do
    with raw_id when is_binary(raw_id) <- session["user_id"],
         {:ok, _} <- Ecto.UUID.cast(raw_id),
         %{} = user <- Accounts.get_user(raw_id) do
      companies = Companies.list_companies()
      current_company = resolve_company(companies, session["current_company_id"])

      socket =
        socket
        |> assign(:current_user, user)
        |> assign(:companies, companies)
        |> assign(:current_company, current_company)
        |> assign(:current_path, nil)
        |> attach_hook(:set_current_path, :handle_params, fn _params, uri, socket ->
          path = URI.parse(uri).path
          {:cont, assign(socket, :current_path, path)}
        end)

      cond do
        companies == [] && !company_route?(socket) ->
          {:halt, redirect(socket, to: "/companies/new")}

        current_company == nil && companies != [] && !company_route?(socket) ->
          # Auto-select first company
          first = hd(companies)

          socket =
            socket
            |> assign(:current_company, first)

          {:cont, socket}

        true ->
          {:cont, socket}
      end
    else
      _ ->
        socket =
          socket
          |> put_flash(:error, "You must be logged in to access this page.")
          |> redirect(to: "/")

        {:halt, socket}
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
