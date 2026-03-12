defmodule KsefHubWeb.ExportLive.Index do
  @moduledoc """
  LiveView page for bulk invoice exports. Provides a form to configure and trigger
  exports, and lists recent export batches with download links.
  """

  use KsefHubWeb, :live_view

  alias KsefHub.Authorization
  alias KsefHub.Exports
  alias KsefHub.Exports.ExportBatch
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

    batches =
      if company,
        do: Exports.list_batches(company.id, socket.assigns.current_user.id),
        else: []

    {:ok,
     socket
     |> assign(
       page_title: "Exports",
       date_from: Date.to_iso8601(first_of_month),
       date_to: Date.to_iso8601(today),
       invoice_type: "expense",
       only_new: false,
       preview_count: nil,
       batches_count: length(batches)
     )
     |> stream(:batches, batches)}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("update_form", params, socket) do
    {:noreply,
     socket
     |> assign(
       date_from: params["date_from"] || socket.assigns.date_from,
       date_to: params["date_to"] || socket.assigns.date_to,
       invoice_type: params["invoice_type"] || socket.assigns.invoice_type,
       only_new: params["only_new"] == "true"
     )
     |> assign(preview_count: nil)}
  end

  def handle_event("preview", _params, socket) do
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
            user_id: socket.assigns.current_user.id
          }

          count = Exports.count_exportable_invoices(company.id, filters)
          {:noreply, assign(socket, preview_count: count)}
        else
          _ ->
            {:noreply, put_flash(socket, :error, "Invalid date format.")}
        end
    end
  end

  def handle_event("export", _params, socket) do
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
      only_new: socket.assigns.only_new
    }

    case Exports.create_export(user.id, company.id, params) do
      {:ok, batch} ->
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
    <.header>
      Exports
      <:subtitle>Download batches of invoices as ZIP files with PDF and CSV summary</:subtitle>
    </.header>

    <div class="mt-6 grid grid-cols-1 lg:grid-cols-3 gap-6">
      <%!-- New Export Form --%>
      <div class="rounded-xl border border-border bg-card text-card-foreground lg:col-span-1">
        <div class="p-6">
          <h2 class="text-base font-semibold">New Export</h2>

          <form phx-change="update_form" phx-submit="export" class="space-y-4">
            <div class="space-y-1">
              <label class="label"><span class="text-sm font-medium">From</span></label>
              <input
                type="date"
                name="date_from"
                value={@date_from}
                class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm shadow-sm"
              />
            </div>

            <div class="space-y-1">
              <label class="label"><span class="text-sm font-medium">To</span></label>
              <input
                type="date"
                name="date_to"
                value={@date_to}
                class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm shadow-sm"
              />
            </div>

            <div class="space-y-1">
              <label class="label"><span class="text-sm font-medium">Invoice Type</span></label>
              <select
                name="invoice_type"
                class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm shadow-sm"
              >
                <option value="expense" selected={@invoice_type == "expense"}>Expenses</option>
                <option value="income" selected={@invoice_type == "income"}>Income</option>
                <option value="" selected={@invoice_type == ""}>All</option>
              </select>
            </div>

            <div class="space-y-1">
              <label class="label cursor-pointer justify-start gap-2">
                <input type="hidden" name="only_new" value="false" />
                <input
                  type="checkbox"
                  name="only_new"
                  value="true"
                  checked={@only_new}
                  class="checkbox checkbox-sm"
                />
                <span class="text-sm font-medium">
                  Only new invoices (not previously exported by me)
                </span>
              </label>
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
              <button
                type="button"
                phx-click="preview"
                class="inline-flex items-center justify-center gap-2 h-9 px-3 text-sm font-medium rounded-md border border-input bg-background hover:bg-shad-accent hover:text-shad-accent-foreground shadow-xs transition-colors cursor-pointer flex-1"
              >
                <.icon name="hero-eye" class="size-4" /> Preview
              </button>
              <button
                type="submit"
                class="inline-flex items-center justify-center gap-2 h-9 px-3 text-sm font-medium rounded-md bg-shad-primary text-shad-primary-foreground hover:bg-shad-primary/90 shadow-xs transition-colors cursor-pointer flex-1"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Export
              </button>
            </div>
          </form>
        </div>
      </div>

      <%!-- Downloads List --%>
      <div class="lg:col-span-2">
        <h2 class="text-base font-semibold mb-4">Downloads</h2>

        <div id="batches" phx-update="stream" class="space-y-3">
          <div
            :for={{dom_id, batch} <- @streams.batches}
            id={dom_id}
            class="rounded-xl border border-border bg-card text-card-foreground"
          >
            <div class="p-6 p-4 flex flex-row items-center justify-between gap-4">
              <div class="flex-1 min-w-0">
                <div class="font-medium text-sm">
                  {batch.date_from} &mdash; {batch.date_to}
                  <span
                    :if={batch.invoice_type}
                    class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border ml-1"
                  >
                    {batch.invoice_type}
                  </span>
                  <span
                    :if={batch.only_new}
                    class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border ml-1"
                  >
                    new only
                  </span>
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
                <span
                  :if={batch.status in [:pending, :processing]}
                  class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border border-info/20 text-info gap-1"
                >
                  <span class="loading loading-spinner loading-xs"></span> Processing
                </span>
                <.link
                  :if={batch.status == :completed}
                  href={~p"/c/#{@current_company.id}/exports/#{batch.id}/download"}
                  target="_blank"
                  class="inline-flex items-center justify-center gap-2 h-9 px-3 text-sm font-medium rounded-md bg-success text-success-content hover:bg-success/90 shadow-xs transition-colors cursor-pointer gap-1"
                >
                  <.icon name="hero-arrow-down-tray" class="size-4" /> Download ZIP
                </.link>
                <span
                  :if={batch.status == :failed}
                  class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border border-error/20 text-error"
                >
                  Failed
                </span>
              </div>
            </div>
          </div>
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
    """
  end

  @spec normalize_type(String.t()) :: String.t() | nil
  defp normalize_type(""), do: nil
  defp normalize_type(type), do: type

  @spec format_datetime(DateTime.t() | NaiveDateTime.t() | nil) :: String.t()
  defp format_datetime(nil), do: "-"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
end
