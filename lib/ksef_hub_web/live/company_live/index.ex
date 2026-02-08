defmodule KsefHubWeb.CompanyLive.Index do
  @moduledoc """
  LiveView for managing companies — list, create, and edit.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Companies
  alias KsefHub.Companies.Company
  alias KsefHub.Credentials

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Companies")
     |> load_companies()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

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

  defp load_companies(socket) do
    companies =
      Companies.list_companies()
      |> Enum.map(fn company ->
        credential = Credentials.get_active_credential(company.id)
        Map.put(company, :active_credential, credential)
      end)

    assign(socket, :companies_with_creds, companies)
  end

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
    <div :if={@form} class="card bg-base-100 shadow-sm mt-6">
      <div class="card-body">
        <h2 class="card-title text-base">
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
          <span :if={company.active_credential} class="badge badge-success badge-sm">Active</span>
          <span :if={!company.active_credential} class="badge badge-ghost badge-sm">None</span>
        </:col>
        <:col :let={company} label="Status">
          <span :if={company.is_active} class="badge badge-success badge-sm">Active</span>
          <span :if={!company.is_active} class="badge badge-ghost badge-sm">Inactive</span>
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
