defmodule KsefHubWeb.ExportLive.Index do
  @moduledoc """
  LiveView page for bulk invoice exports. Provides a form to configure and trigger
  exports, and lists recent export batches with download links.
  """

  use KsefHubWeb, :live_view

  import KsefHubWeb.InvoiceComponents, only: [format_datetime: 1]
  import KsefHubWeb.SettingsComponents, only: [settings_layout: 1]

  alias KsefHub.Authorization
  alias KsefHub.Exports
  alias KsefHub.Exports.ExportBatch
  alias KsefHub.Invoices
  alias KsefHub.Repo

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    company = socket.assigns.current_company

    if connected?(socket) && company do
      Phoenix.PubSub.subscribe(KsefHub.PubSub, "exports:#{company.id}")
    end

    today = Date.utc_today()
    first_of_month = Date.beginning_of_month(today)

    {batches, categories} =
      if company do
        {
          Exports.list_batches(company.id, socket.assigns.current_user.id),
          Invoices.list_categories(company.id)
        }
      else
        {[], []}
      end

    {:ok,
     socket
     |> assign(
       page_title: "Exports",
       date_from: Date.to_iso8601(first_of_month),
       date_to: Date.to_iso8601(today),
       invoice_type: "expense",
       only_new: true,
       category_id: nil,
       categories: categories,
       preview_count: nil,
       batches_count: length(batches)
     )
     |> stream(:batches, batches)}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("update_form", params, socket) do
    invoice_type = params["invoice_type"] || socket.assigns.invoice_type

    category_id =
      params
      |> Map.get("category_id")
      |> normalize_category_id()
      |> category_id_for_type(invoice_type)

    {:noreply,
     socket
     |> assign(
       date_from: params["date_from"] || socket.assigns.date_from,
       date_to: params["date_to"] || socket.assigns.date_to,
       invoice_type: invoice_type,
       only_new: params["only_new"] == "true",
       category_id: category_id
     )
     |> assign(preview_count: nil)}
  end

  def handle_event("export", params, socket) do
    invoice_type = params["invoice_type"] || socket.assigns.invoice_type

    category_id =
      params
      |> Map.get("category_id")
      |> normalize_category_id()
      |> category_id_for_type(invoice_type)

    socket =
      socket
      |> assign(
        date_from: params["date_from"] || socket.assigns.date_from,
        date_to: params["date_to"] || socket.assigns.date_to,
        invoice_type: invoice_type,
        only_new: params["only_new"] == "true",
        category_id: category_id
      )

    case params["_action"] do
      "preview" -> do_preview(socket)
      _ -> do_export_action(socket)
    end
  end

  @spec do_preview(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_preview(socket) do
    case socket.assigns.current_company do
      nil ->
        {:noreply, socket}

      company ->
        with {:ok, date_from} <- Date.from_iso8601(socket.assigns.date_from),
             {:ok, date_to} <- Date.from_iso8601(socket.assigns.date_to) do
          filters = %{
            date_from: date_from,
            date_to: date_to,
            invoice_type: normalize_type(socket.assigns.invoice_type),
            only_new: socket.assigns.only_new,
            user_id: socket.assigns.current_user.id,
            category_id: socket.assigns.category_id
          }

          count = Exports.count_exportable_invoices(company.id, filters)
          {:noreply, assign(socket, preview_count: count)}
        else
          _ ->
            {:noreply, put_flash(socket, :error, "Invalid date format.")}
        end
    end
  end

  @spec do_export_action(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_export_action(socket) do
    cond do
      is_nil(socket.assigns.current_company) ->
        {:noreply, socket}

      not Authorization.can?(socket.assigns[:current_role], :create_export) ->
        {:noreply, put_flash(socket, :error, "You don't have permission to create exports.")}

      true ->
        do_export(socket, socket.assigns.current_company)
    end
  end

  @spec do_export(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_export(socket, company) do
    user = socket.assigns.current_user

    params = %{
      date_from: socket.assigns.date_from,
      date_to: socket.assigns.date_to,
      invoice_type: normalize_type(socket.assigns.invoice_type),
      only_new: socket.assigns.only_new,
      category_id: socket.assigns.category_id
    }

    case Exports.create_export(user.id, company.id, params, actor_opts(socket)) do
      {:ok, batch} ->
        batch = Repo.preload(batch, [:category])

        {:noreply,
         socket
         |> stream_insert(:batches, batch, at: 0)
         |> update(:batches_count, &(&1 + 1))
         |> assign(preview_count: nil)
         |> put_flash(:info, "Export started. You'll be notified when it's ready.")}

      {:error, changeset} ->
        message =
          changeset
          |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
          |> Enum.map_join(", ", fn {field, msgs} ->
            "#{field}: #{Enum.join(msgs, ", ")}"
          end)

        {:noreply, put_flash(socket, :error, "Export failed: #{message}")}
    end
  end

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:export_status, batch_id, _status}, socket) do
    company = socket.assigns.current_company
    user = socket.assigns.current_user

    case Repo.get(ExportBatch, batch_id) do
      nil ->
        {:noreply, socket}

      batch ->
        if batch.company_id == company.id and batch.user_id == user.id do
          batch = Repo.preload(batch, [:category])
          {:noreply, stream_insert(socket, :batches, batch)}
        else
          {:noreply, socket}
        end
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
        Exports
        <:subtitle>Download batches of invoices as ZIP files with PDF and CSV summary</:subtitle>
      </.header>

      <div class="mt-6 grid grid-cols-1 lg:grid-cols-3 gap-6">
        <%!-- New Export Form --%>
        <.card class="lg:col-span-1">
          <h2 class="text-base font-semibold">New Export</h2>

          <form phx-change="update_form" phx-submit="export" class="space-y-4">
            <div class="space-y-1">
              <label class="label"><span class="text-sm font-medium">Issue Date Range</span></label>
              <.date_range_picker
                id="export-date-range"
                from_name="date_from"
                to_name="date_to"
                from_value={@date_from}
                to_value={@date_to}
                size="default"
              />
            </div>

            <div class="space-y-1">
              <label class="label"><span class="text-sm font-medium">Invoice Type</span></label>
              <select
                name="invoice_type"
                class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
              >
                <option value="expense" selected={@invoice_type == "expense"}>Expenses</option>
                <option value="income" selected={@invoice_type == "income"}>Income</option>
                <option value="" selected={@invoice_type == ""}>All</option>
              </select>
            </div>

            <div class="space-y-1">
              <label class="label">
                <span class="text-sm font-medium">Category</span>
                <span
                  :if={@invoice_type != "expense"}
                  class="text-xs text-muted-foreground font-normal"
                >
                  — expense only
                </span>
              </label>
              <select
                name="category_id"
                disabled={@invoice_type != "expense"}
                class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50"
              >
                <option value="" selected={is_nil(@category_id)}>All categories</option>
                <option
                  :for={cat <- @categories}
                  value={cat.id}
                  selected={@category_id == cat.id}
                >
                  {cat.name || cat.identifier}
                </option>
              </select>
            </div>

            <div>
              <input type="hidden" name="only_new" value="false" />
              <label class="flex cursor-pointer items-center gap-2">
                <input
                  type="checkbox"
                  name="only_new"
                  value="true"
                  checked={@only_new}
                  class="size-4 shrink-0 rounded border border-input bg-background accent-shad-primary"
                />
                <span class="text-sm font-medium">New invoices only</span>
              </label>
              <p class="text-xs text-muted-foreground mt-0.5 ml-6">
                Export invoices not previously exported by me
              </p>
            </div>

            <div
              :if={@preview_count != nil}
              class="rounded-md border border-blue-200 bg-blue-50 dark:border-blue-900 dark:bg-blue-950 p-4 text-sm"
            >
              <.icon name="hero-information-circle" class="size-5" />
              <span>
                {@preview_count} invoice{if @preview_count != 1, do: "s"} match{if @preview_count ==
                                                                                     1,
                                                                                   do: "es"} your filters.
              </span>
            </div>

            <div class="flex gap-2">
              <.button type="submit" name="_action" value="preview" variant="outline" class="flex-1">
                <.icon name="hero-eye" class="size-4" /> Preview
              </.button>
              <.button type="submit" name="_action" value="export" class="flex-1">
                <.icon name="hero-arrow-down-tray" class="size-4" /> Export
              </.button>
            </div>

            <p class="text-xs text-muted-foreground">
              Approved expense invoices and all income invoices are included.
              Excluded invoices (hidden from analytics) are still exported.
            </p>
          </form>
        </.card>

        <%!-- Downloads List --%>
        <div class="lg:col-span-2">
          <h2 class="text-base font-semibold mb-4">Downloads</h2>

          <div id="batches" phx-update="stream" class="space-y-3">
            <.card
              :for={{dom_id, batch} <- @streams.batches}
              id={dom_id}
              padding="p-4 flex flex-row items-center justify-between gap-4"
            >
              <div class="flex-1 min-w-0">
                <div class="font-medium text-sm">
                  {batch.date_from} &mdash; {batch.date_to}
                  <.badge :if={batch.invoice_type} variant="default" class="ml-1">
                    {batch.invoice_type}
                  </.badge>
                  <.badge :if={match?(%{id: _}, batch.category)} variant="default" class="ml-1">
                    {batch.category.name || batch.category.identifier}
                  </.badge>
                  <.badge :if={batch.only_new} variant="default" class="ml-1">
                    new only
                  </.badge>
                </div>
                <div class="text-xs text-muted-foreground mt-0.5">
                  {format_datetime(batch.inserted_at)}
                  <span :if={batch.invoice_count}>
                    &middot; {batch.invoice_count} invoices
                  </span>
                </div>
                <div
                  :if={batch.status == :failed && batch.error_message}
                  class="text-xs text-shad-destructive mt-1 truncate"
                >
                  {batch.error_message}
                </div>
              </div>

              <div class="flex-shrink-0">
                <.badge :if={batch.status in [:pending, :processing]} variant="info" class="gap-1">
                  <span class="loading loading-spinner loading-xs"></span> Processing
                </.badge>
                <.button
                  :if={batch.status == :completed}
                  variant="success"
                  href={~p"/c/#{@current_company.id}/exports/#{batch.id}/download"}
                  target="_blank"
                >
                  <.icon name="hero-arrow-down-tray" class="size-4" /> Download ZIP
                </.button>
                <.badge :if={batch.status == :failed} variant="error">Failed</.badge>
              </div>
            </.card>
          </div>

          <div :if={@batches_count == 0} class="text-center py-12">
            <.icon
              name="hero-arrow-down-tray"
              class="size-8 text-muted-foreground mx-auto mb-2"
            />
            <p class="text-muted-foreground">
              No exports yet. Configure filters and click Export to get started.
            </p>
          </div>
        </div>
      </div>
    </.settings_layout>
    """
  end

  @spec normalize_type(String.t()) :: String.t() | nil
  defp normalize_type(""), do: nil
  defp normalize_type(type), do: type

  @spec normalize_category_id(String.t() | nil) :: Ecto.UUID.t() | nil
  defp normalize_category_id(""), do: nil
  defp normalize_category_id(nil), do: nil
  defp normalize_category_id(id), do: id

  @spec category_id_for_type(Ecto.UUID.t() | nil, String.t()) :: Ecto.UUID.t() | nil
  defp category_id_for_type(_category_id, invoice_type) when invoice_type != "expense", do: nil
  defp category_id_for_type(category_id, _invoice_type), do: category_id
end
