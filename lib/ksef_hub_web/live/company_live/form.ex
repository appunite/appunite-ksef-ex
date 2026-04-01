defmodule KsefHubWeb.CompanyLive.Form do
  @moduledoc """
  LiveView for creating or editing a company.

  Edit mode includes inbound email configuration (enable/disable/regenerate,
  allowed sender domain, CC email).
  """
  use KsefHubWeb, :live_view

  require Logger

  alias KsefHub.Authorization
  alias KsefHub.Companies
  alias KsefHub.Companies.Company
  alias KsefHub.Credentials
  alias KsefHub.KsefClient.AuthWorker

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       can_manage_company: Authorization.can?(socket.assigns[:current_role], :manage_company)
     )}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @spec apply_action(Phoenix.LiveView.Socket.t(), atom(), map()) :: Phoenix.LiveView.Socket.t()
  defp apply_action(socket, :new, _params) do
    socket
    |> assign(
      page_title: "New Company",
      company: %Company{},
      form: to_form(Company.changeset(%Company{}, %{})),
      inbound_settings_form: nil,
      inbound_domain_configured: false
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    if socket.assigns.can_manage_company do
      company = Companies.get_company!(id)

      socket
      |> assign(
        page_title: "Edit #{company.name}",
        company: company,
        inbound_domain_configured: Application.get_env(:ksef_hub, :inbound_email_domain) != nil,
        form: to_form(Company.changeset(company, %{})),
        inbound_settings_form: to_form(Company.inbound_email_settings_changeset(company, %{}))
      )
    else
      socket
      |> put_flash(:error, "You don't have permission to edit companies.")
      |> push_navigate(to: ~p"/companies")
    end
  end

  # --- Authorization guard for mutation events ---

  @new_company_events ~w(save validate)
  @company_mutation_events ~w(save validate enable_inbound_email disable_inbound_email
    regenerate_inbound_email validate_inbound_settings save_inbound_settings)

  @impl true
  def handle_event(
        event,
        _params,
        %{assigns: %{can_manage_company: false, live_action: :new}} = socket
      )
      when event in @company_mutation_events and event not in @new_company_events do
    {:noreply, put_flash(socket, :error, "You don't have permission to manage companies.")}
  end

  @impl true
  def handle_event(
        event,
        _params,
        %{assigns: %{can_manage_company: false, live_action: action}} = socket
      )
      when event in @company_mutation_events and action != :new do
    {:noreply, put_flash(socket, :error, "You don't have permission to manage companies.")}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
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

  # --- Private helpers ---

  @spec save_company(Phoenix.LiveView.Socket.t(), atom(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp save_company(socket, :new, params) do
    user = socket.assigns.current_user

    case Companies.create_company_with_owner(user, params) do
      {:ok, %{company: company}} ->
        maybe_setup_credential(user, company)

        {:noreply,
         socket
         |> put_flash(:info, "Company created.")
         |> redirect(to: ~p"/c/#{company.id}/invoices")}

      {:error, _failed_step, changeset, _changes} ->
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

  @spec maybe_setup_credential(KsefHub.Accounts.User.t(), Company.t()) :: :ok
  defp maybe_setup_credential(user, company) do
    with cert when not is_nil(cert) <- Credentials.get_active_user_certificate(user.id),
         {:ok, _credential} <- Credentials.ensure_credential_for_company(company.id) do
      enqueue_auth(company.id)
    end

    :ok
  end

  @spec enqueue_auth(Ecto.UUID.t()) :: :ok
  defp enqueue_auth(company_id) do
    case %{company_id: company_id} |> AuthWorker.new() |> Oban.insert() do
      {:ok, _job} -> :ok
      {:error, _reason} -> Logger.error("Failed to enqueue auth job for company #{company_id}")
    end
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

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.header>
      {if @live_action == :new, do: "New Company", else: "Edit #{@company.name}"}
      <:subtitle>
        {if @live_action == :new,
          do: "Create a new company",
          else: "Update company details and settings"}
      </:subtitle>
    </.header>

    <.form
      for={@form}
      phx-submit="save"
      phx-change="validate"
      class="mt-6 space-y-6 max-w-xl"
      id="company-form"
    >
      <.input field={@form[:name]} label="Company Name" placeholder="Acme Sp. z o.o." required />
      <.input
        field={@form[:nip]}
        label="NIP (10 digits)"
        placeholder="1234567890"
        required
        disabled={@live_action == :edit}
      />
      <.input field={@form[:address]} label="Address" placeholder="ul. Testowa 1, Warszawa" />

      <div class="flex items-center gap-3 pt-2">
        <.button type="submit">
          {if @live_action == :new, do: "Create Company", else: "Save"}
        </.button>
        <.button variant="outline" navigate={~p"/companies"}>
          Cancel
        </.button>
      </div>
    </.form>

    <%!-- Inbound Email Section (edit mode only) --%>
    <.card :if={@live_action == :edit && @company.id} class="mt-8" padding="p-6 space-y-4">
      <div class="flex items-center justify-between">
        <h2 class="text-base font-semibold">Inbound Email</h2>
        <.badge :if={@company.inbound_email_token_hash} variant="success">Enabled</.badge>
        <.badge :if={!@company.inbound_email_token_hash} variant="muted">Disabled</.badge>
      </div>

      <div
        :if={@company.inbound_email_token}
        id="inbound-email-display"
        class="bg-muted px-4 py-3 rounded-lg"
      >
        <p class="text-xs text-muted-foreground mb-1">Email address</p>
        <code data-testid="inbound-email-address" class="select-all text-sm font-mono break-all">
          {inbound_email_address(@company)}
        </code>
        <p :if={!@inbound_domain_configured} class="text-xs text-warning mt-1">
          INBOUND_EMAIL_DOMAIN not configured — set it to display the full address.
        </p>
      </div>

      <div class="flex gap-2">
        <.button
          :if={!@company.inbound_email_token_hash}
          type="button"
          phx-click="enable_inbound_email"
        >
          Enable Inbound Email
        </.button>
        <.button
          :if={@company.inbound_email_token_hash}
          variant="warning"
          type="button"
          phx-click="regenerate_inbound_email"
          data-confirm="This will invalidate the current inbound email address. Continue?"
        >
          Regenerate Address
        </.button>
        <.button
          :if={@company.inbound_email_token_hash}
          variant="outline"
          class="border-shad-destructive text-shad-destructive hover:bg-shad-destructive/10"
          type="button"
          phx-click="disable_inbound_email"
          data-confirm="This will disable inbound email processing for this company. Continue?"
        >
          Disable
        </.button>
      </div>

      <div :if={@inbound_settings_form} class="border-t border-border pt-4">
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
          <p class="text-xs text-muted-foreground -mt-2">
            Only accept inbound emails from this domain. Leave empty to allow any sender.
          </p>
          <.input
            field={@inbound_settings_form[:inbound_cc_email]}
            label="CC email"
            placeholder="invoices@appunite.com"
            phx-debounce="blur"
          />
          <p class="text-xs text-muted-foreground -mt-2">
            CC this address on all reply notifications. Leave empty for no CC.
          </p>
          <.button type="submit">Save Settings</.button>
        </.form>
      </div>
    </.card>
    """
  end
end
