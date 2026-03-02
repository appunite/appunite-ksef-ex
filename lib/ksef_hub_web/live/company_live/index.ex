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
    |> assign(:inbound_settings_form, nil)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    company = Companies.get_company!(id)

    socket
    |> assign(:page_title, "Edit #{company.name}")
    |> assign(:company, company)
    |> assign(
      :inbound_domain_configured,
      Application.get_env(:ksef_hub, :inbound_email_domain) != nil
    )
    |> assign(:form, to_form(Companies.Company.changeset(company, %{})))
    |> assign(
      :inbound_settings_form,
      to_form(Company.inbound_email_settings_changeset(company, %{}))
    )
  end

  defp apply_action(socket, _action, _params) do
    socket
    |> assign(:company, nil)
    |> assign(:form, nil)
    |> assign(:inbound_settings_form, nil)
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

  @impl true
  def handle_event(
        "enable_inbound_email",
        _params,
        %{assigns: %{company: %Company{} = company}} = socket
      ) do
    case Companies.enable_inbound_email(company) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign_inbound_state(updated)
         |> put_flash(:info, "Inbound email enabled.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to enable inbound email.")}
    end
  end

  @impl true
  def handle_event(
        "disable_inbound_email",
        _params,
        %{assigns: %{company: %Company{} = company}} = socket
      ) do
    case Companies.disable_inbound_email(company) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign_inbound_state(updated)
         |> put_flash(:info, "Inbound email disabled.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to disable inbound email.")}
    end
  end

  @impl true
  def handle_event(
        "regenerate_inbound_email",
        _params,
        %{assigns: %{company: %Company{} = company}} = socket
      ) do
    # enable_inbound_email/1 overwrites the existing token, no need to disable first
    case Companies.enable_inbound_email(company) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign_inbound_state(updated)
         |> put_flash(:info, "Inbound email address regenerated.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to regenerate inbound email.")}
    end
  end

  @impl true
  def handle_event(
        "validate_inbound_settings",
        %{"company" => params},
        %{assigns: %{company: %Company{} = company}} = socket
      ) do
    changeset =
      company
      |> Company.inbound_email_settings_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, inbound_settings_form: to_form(changeset))}
  end

  @impl true
  def handle_event(
        "save_inbound_settings",
        %{"company" => params},
        %{assigns: %{company: %Company{} = company}} = socket
      ) do
    case Companies.update_inbound_email_settings(company, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign_inbound_state(updated)
         |> put_flash(:info, "Inbound email settings saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, inbound_settings_form: to_form(changeset))}
    end
  end

  def handle_event(event, _params, socket)
      when event in ~w(enable_inbound_email disable_inbound_email regenerate_inbound_email validate_inbound_settings save_inbound_settings) do
    {:noreply, socket}
  end

  @spec save_company(Phoenix.LiveView.Socket.t(), atom(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp save_company(socket, :new, params) do
    user = socket.assigns.current_user

    case Companies.create_company_with_owner(user, params) do
      {:ok, %{company: company}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Company created.")
         |> redirect(to: ~p"/switch-company/#{company.id}?return_to=/invoices")}

      {:error, :company, changeset, _changes} ->
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
    user = socket.assigns.current_user

    assign(
      socket,
      :companies_with_creds,
      Companies.list_companies_for_user_with_credential_status(user.id)
    )
  end

  @spec assign_inbound_state(Phoenix.LiveView.Socket.t(), Company.t()) ::
          Phoenix.LiveView.Socket.t()
  defp assign_inbound_state(socket, company) do
    socket
    |> assign(:company, company)
    |> assign(
      :inbound_settings_form,
      to_form(Company.inbound_email_settings_changeset(company, %{}))
    )
  end

  @spec inbound_email_address(Company.t()) :: String.t() | nil
  defp inbound_email_address(%{inbound_email_token: nil}), do: nil

  defp inbound_email_address(%{inbound_email_token: token}) do
    case Application.get_env(:ksef_hub, :inbound_email_domain) do
      nil -> token
      domain -> "inv-#{token}@#{domain}"
    end
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

    <!-- Inbound Email Section (edit mode only) -->
    <div :if={@live_action == :edit && @company} class="card bg-base-100 border border-base-300 mt-6">
      <div class="p-5 space-y-4">
        <div class="flex items-center justify-between">
          <h2 class="text-base font-semibold">Inbound Email</h2>
          <span
            :if={@company.inbound_email_token_hash}
            class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border bg-success/10 text-success border-success/20"
          >
            Enabled
          </span>
          <span
            :if={!@company.inbound_email_token_hash}
            class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border bg-base-200 text-base-content/60 border-base-300"
          >
            Disabled
          </span>
        </div>
        
    <!-- Inbound email address display -->
        <div
          :if={@company.inbound_email_token}
          id="inbound-email-display"
          class="bg-base-200 px-4 py-3 rounded-lg"
        >
          <p class="text-xs text-base-content/60 mb-1">Email address</p>
          <code data-testid="inbound-email-address" class="select-all text-sm font-mono break-all">
            {inbound_email_address(@company)}
          </code>
          <p
            :if={!@inbound_domain_configured}
            class="text-xs text-warning mt-1"
          >
            INBOUND_EMAIL_DOMAIN not configured — set it to display the full address.
          </p>
        </div>
        
    <!-- Enable / Disable / Regenerate buttons -->
        <div class="flex gap-2">
          <button
            :if={!@company.inbound_email_token_hash}
            type="button"
            phx-click="enable_inbound_email"
            class="btn btn-primary btn-sm"
          >
            Enable Inbound Email
          </button>
          <button
            :if={@company.inbound_email_token_hash}
            type="button"
            phx-click="regenerate_inbound_email"
            data-confirm="This will invalidate the current inbound email address. Continue?"
            class="btn btn-warning btn-sm"
          >
            Regenerate Address
          </button>
          <button
            :if={@company.inbound_email_token_hash}
            type="button"
            phx-click="disable_inbound_email"
            data-confirm="This will disable inbound email processing for this company. Continue?"
            class="btn btn-error btn-outline btn-sm"
          >
            Disable
          </button>
        </div>
        
    <!-- Inbound email settings form -->
        <div :if={@inbound_settings_form} class="border-t border-base-300 pt-4">
          <h3 class="text-sm font-medium mb-3">Settings</h3>
          <.form
            for={@inbound_settings_form}
            phx-submit="save_inbound_settings"
            phx-change="validate_inbound_settings"
            class="space-y-4"
          >
            <.input
              field={@inbound_settings_form[:inbound_allowed_sender_domain]}
              label="Allowed sender domain"
              placeholder="appunite.com"
              phx-debounce="blur"
            />
            <p class="text-xs text-base-content/60 -mt-2">
              Only accept inbound emails from this domain. Leave empty to allow any sender.
            </p>
            <.input
              field={@inbound_settings_form[:inbound_cc_email]}
              label="CC email"
              placeholder="invoices@appunite.com"
              phx-debounce="blur"
            />
            <p class="text-xs text-base-content/60 -mt-2">
              CC this address on all reply notifications. Leave empty for no CC.
            </p>
            <button type="submit" class="btn btn-primary btn-sm">Save Settings</button>
          </.form>
        </div>
      </div>
    </div>

    <!-- Company List -->
    <div class="mt-6 overflow-x-auto">
      <.table
        id="companies"
        rows={@companies_with_creds}
        row_id={fn c -> "company-#{c.id}" end}
      >
        <:col :let={company} label="Name">
          <span data-testid="company-name">{company.name}</span>
        </:col>
        <:col :let={company} label="NIP">
          <span class="font-mono">{company.nip}</span>
        </:col>
        <:col :let={company} label="KSeF Sync">
          <span
            :if={company.has_active_credential}
            class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border bg-success/10 text-success border-success/20"
          >
            Configured
          </span>
          <span
            :if={!company.has_active_credential}
            class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border bg-base-200 text-base-content/60 border-base-300"
          >
            Not configured
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
