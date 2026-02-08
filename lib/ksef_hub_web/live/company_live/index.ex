defmodule KsefHubWeb.CompanyLive.Index do
  @moduledoc """
  LiveView for managing companies — list, create, and edit.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Companies
  alias KsefHub.Companies.Company

  @doc "Loads companies with credential status on mount."
  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Companies")
     |> load_companies()}
  end

  @doc "Applies the current live_action (:index, :new, :edit) to the socket."
  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @spec apply_action(Phoenix.LiveView.Socket.t(), atom(), map()) :: Phoenix.LiveView.Socket.t()
  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Company")
    |> assign(:company, %Company{})
    |> assign(:form, to_form(Companies.Company.changeset(%Company{}, %{})))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    company = Companies.get_company!(id)

    socket
    |> assign(:page_title, "Edit #{company.name}")
    |> assign(:company, company)
    |> assign(:form, to_form(Companies.Company.changeset(company, %{})))
  end

  defp apply_action(socket, _action, _params) do
    socket
    |> assign(:company, nil)
    |> assign(:form, nil)
  end

  @doc "Handles form validation and save events."
  @impl true
  def handle_event("validate", %{"company" => params}, socket) do
    changeset =
      socket.assigns.company
      |> Company.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"company" => params}, socket) do
    save_company(socket, socket.assigns.live_action, params)
  end

  @spec save_company(Phoenix.LiveView.Socket.t(), atom(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp save_company(socket, :new, params) do
    case Companies.create_company(params) do
      {:ok, company} ->
        {:noreply,
         socket
         |> put_flash(:info, "Company created.")
         |> redirect(to: ~p"/switch-company/#{company.id}?return_to=/dashboard")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_company(socket, :edit, params) do
    case Companies.update_company(socket.assigns.company, params) do
      {:ok, _company} ->
        {:noreply,
         socket
         |> put_flash(:info, "Company updated.")
         |> push_navigate(to: ~p"/companies")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @spec load_companies(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_companies(socket) do
    assign(socket, :companies_with_creds, Companies.list_companies_with_credential_status())
  end

  @doc "Renders the company list page with create/edit form."
  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Companies
      <:subtitle>Manage your companies</:subtitle>
      <:actions>
        <.link navigate={~p"/companies/new"} class="btn btn-primary btn-sm">
          <.icon name="hero-plus" class="size-4" /> New Company
        </.link>
      </:actions>
    </.header>

    <!-- Company Form Modal -->
    <div :if={@form} class="card bg-base-100 border border-base-300 mt-6">
      <div class="p-5">
        <h2 class="text-base font-semibold">
          {if @live_action == :new, do: "Create New Company", else: "Edit Company"}
        </h2>
        <form phx-submit="save" phx-change="validate" class="space-y-4 mt-2">
          <.input field={@form[:name]} label="Company Name" placeholder="Acme Sp. z o.o." required />
          <.input
            field={@form[:nip]}
            label="NIP (10 digits)"
            placeholder="1234567890"
            required
            disabled={@live_action == :edit}
          />
          <.input field={@form[:address]} label="Address" placeholder="ul. Testowa 1, Warszawa" />
          <div class="flex gap-2">
            <button type="submit" class="btn btn-primary btn-sm">
              {if @live_action == :new, do: "Create", else: "Save"}
            </button>
            <.link navigate={~p"/companies"} class="btn btn-ghost btn-sm">Cancel</.link>
          </div>
        </form>
      </div>
    </div>

    <!-- Company List -->
    <div class="mt-6 overflow-x-auto">
      <.table
        id="companies"
        rows={@companies_with_creds}
        row_id={fn c -> "company-#{c.id}" end}
      >
        <:col :let={company} label="Name">{company.name}</:col>
        <:col :let={company} label="NIP">
          <span class="font-mono">{company.nip}</span>
        </:col>
        <:col :let={company} label="Certificate">
          <span
            :if={company.has_active_credential}
            class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border bg-success/10 text-success border-success/20"
          >
            Active
          </span>
          <span
            :if={!company.has_active_credential}
            class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border bg-base-200 text-base-content/60 border-base-300"
          >
            None
          </span>
        </:col>
        <:col :let={company} label="Status">
          <span
            :if={company.is_active}
            class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border bg-success/10 text-success border-success/20"
          >
            Active
          </span>
          <span
            :if={!company.is_active}
            class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border bg-base-200 text-base-content/60 border-base-300"
          >
            Inactive
          </span>
        </:col>
        <:action :let={company}>
          <.link navigate={~p"/companies/#{company.id}/edit"} class="btn btn-ghost btn-xs">
            Edit
          </.link>
        </:action>
      </.table>
    </div>

    <p :if={@companies_with_creds == []} class="text-center text-base-content/60 py-8">
      No companies yet. Create one to get started.
    </p>
    """
  end
end
