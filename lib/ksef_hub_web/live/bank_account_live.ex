defmodule KsefHubWeb.BankAccountLive do
  @moduledoc """
  LiveView for managing company bank accounts.

  Bank accounts are used as the orderer account (rachunek_zleceniodawcy)
  when exporting payment requests to CSV. One account per currency per company.
  """
  use KsefHubWeb, :live_view

  import KsefHubWeb.SettingsComponents, only: [settings_layout: 1]

  alias KsefHub.Companies
  alias KsefHub.Companies.CompanyBankAccount

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    company_id = socket.assigns.current_company.id
    bank_accounts = Companies.list_bank_accounts(company_id)

    {:ok,
     socket
     |> assign(page_title: "Bank Accounts", accounts_count: length(bank_accounts))
     |> stream(:bank_accounts, bank_accounts)
     |> assign(editing: nil, form: nil)}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("new", _params, socket) do
    changeset = CompanyBankAccount.changeset(%CompanyBankAccount{}, %{})
    {:noreply, assign(socket, editing: :new, form: to_form(changeset, as: :bank_account))}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    company_id = socket.assigns.current_company.id

    case find_bank_account(company_id, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Bank account not found.")}

      ba ->
        changeset = CompanyBankAccount.changeset(ba, %{})
        {:noreply, assign(socket, editing: ba, form: to_form(changeset, as: :bank_account))}
    end
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, editing: nil, form: nil)}
  end

  def handle_event("validate", %{"bank_account" => params}, socket) do
    target =
      if socket.assigns.editing == :new, do: %CompanyBankAccount{}, else: socket.assigns.editing

    changeset =
      target
      |> CompanyBankAccount.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :bank_account))}
  end

  def handle_event("save", %{"bank_account" => params}, socket) do
    case socket.assigns.editing do
      :new -> do_create(socket, params)
      %CompanyBankAccount{} = ba -> do_update(socket, ba, params)
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    company_id = socket.assigns.current_company.id

    case find_bank_account(company_id, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Bank account not found.")}

      ba ->
        case Companies.delete_bank_account(ba) do
          {:ok, _} ->
            {:noreply,
             socket
             |> stream_delete(:bank_accounts, ba)
             |> update(:accounts_count, &(&1 - 1))
             |> assign(editing: nil, form: nil)
             |> put_flash(:info, "Bank account for #{ba.currency} deleted.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not delete bank account.")}
        end
    end
  end

  @spec do_create(Phoenix.LiveView.Socket.t(), map()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_create(socket, params) do
    company_id = socket.assigns.current_company.id

    case Companies.create_bank_account(company_id, params) do
      {:ok, ba} ->
        {:noreply,
         socket
         |> stream_insert(:bank_accounts, ba)
         |> update(:accounts_count, &(&1 + 1))
         |> assign(editing: nil, form: nil)
         |> put_flash(:info, "Bank account for #{ba.currency} created.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :bank_account))}
    end
  end

  @spec do_update(Phoenix.LiveView.Socket.t(), CompanyBankAccount.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_update(socket, ba, params) do
    case Companies.update_bank_account(ba, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> stream_insert(:bank_accounts, updated)
         |> assign(editing: nil, form: nil)
         |> put_flash(:info, "Bank account for #{updated.currency} updated.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :bank_account))}
    end
  end

  @spec find_bank_account(Ecto.UUID.t(), String.t()) :: CompanyBankAccount.t() | nil
  defp find_bank_account(company_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Companies.get_bank_account(company_id, uuid)
      :error -> nil
    end
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.settings_layout
      current_path={@current_path}
      current_company={@current_company}
      current_role={@current_role}
    >
      <.header>
        Bank Accounts
        <:subtitle>
          Configure company bank accounts used as the orderer account in payment CSV exports.
          One account per currency.
        </:subtitle>
        <:actions>
          <.button :if={@editing == nil} phx-click="new">
            <.icon name="hero-plus" class="size-4" /> Add Account
          </.button>
        </:actions>
      </.header>

      <%!-- Inline form for new/edit --%>
      <div :if={@form} class="mt-6 p-4 rounded-lg border border-border bg-muted/30">
        <h3 class="text-sm font-medium mb-4">
          {if @editing == :new, do: "New Bank Account", else: "Edit Bank Account"}
        </h3>
        <.form
          for={@form}
          phx-change="validate"
          phx-submit="save"
          class="space-y-4 max-w-md"
        >
          <div class="grid grid-cols-2 gap-3">
            <div class="space-y-1">
              <label for={@form[:currency].id} class="block text-sm font-medium">Currency</label>
              <input
                type="text"
                id={@form[:currency].id}
                name={@form[:currency].name}
                value={@form[:currency].value}
                placeholder="PLN"
                maxlength="3"
                class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm font-mono uppercase focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
                required
                disabled={@editing != :new}
              />
              <.error :for={msg <- Enum.map(@form[:currency].errors, &translate_error/1)}>
                {msg}
              </.error>
            </div>
            <div class="space-y-1">
              <label for={@form[:label].id} class="block text-sm font-medium">
                Label <span class="text-muted-foreground font-normal">(optional)</span>
              </label>
              <input
                type="text"
                id={@form[:label].id}
                name={@form[:label].name}
                value={@form[:label].value}
                placeholder="Main PLN account"
                class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
              />
              <.error :for={msg <- Enum.map(@form[:label].errors, &translate_error/1)}>
                {msg}
              </.error>
            </div>
          </div>

          <div class="space-y-1">
            <label for={@form[:iban].id} class="block text-sm font-medium">IBAN</label>
            <input
              type="text"
              id={@form[:iban].id}
              name={@form[:iban].name}
              value={@form[:iban].value}
              placeholder="PL12105015201000009032123698"
              class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm font-mono focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
              required
            />
            <.error :for={msg <- Enum.map(@form[:iban].errors, &translate_error/1)}>
              {msg}
            </.error>
          </div>

          <div class="flex items-center gap-3">
            <.button type="submit">
              <.icon name="hero-check" class="size-4" />
              {if @editing == :new, do: "Create", else: "Save"}
            </.button>
            <.button type="button" variant="outline" phx-click="cancel">
              Cancel
            </.button>
          </div>
        </.form>
      </div>

      <%!-- Table of existing accounts --%>
      <div :if={@accounts_count > 0} class="rounded-lg border border-border overflow-hidden mt-6">
        <div class="overflow-x-auto">
          <.table
            id="bank-accounts"
            rows={@streams.bank_accounts}
            row_id={fn {id, _} -> id end}
            row_item={fn {_id, item} -> item end}
          >
            <:col :let={ba} label="Currency">
              <span class="font-mono font-medium">{ba.currency}</span>
            </:col>
            <:col :let={ba} label="IBAN">
              <code class="font-mono text-sm">{ba.iban}</code>
            </:col>
            <:col :let={ba} label="Label">
              <span class="text-muted-foreground">{ba.label || "—"}</span>
            </:col>
            <:action :let={ba}>
              <div class="flex gap-2">
                <.button
                  variant="outline"
                  size="sm"
                  phx-click="edit"
                  phx-value-id={ba.id}
                >
                  Edit
                </.button>
                <.button
                  variant="outline"
                  size="sm"
                  class="border-shad-destructive text-shad-destructive hover:bg-shad-destructive/10"
                  phx-click="delete"
                  phx-value-id={ba.id}
                  data-confirm="Delete bank account for #{ba.currency}?"
                >
                  Delete
                </.button>
              </div>
            </:action>
          </.table>
        </div>
      </div>

      <p :if={@accounts_count == 0} class="text-center text-muted-foreground py-8">
        No bank accounts configured. Add one to enable payment CSV exports.
      </p>
    </.settings_layout>
    """
  end
end
