defmodule KsefHubWeb.ExportLive.Index do
  @moduledoc """
  LiveView page for bulk invoice exports. Provides a form to configure and trigger
  exports, and lists recent export batches with download links.
  """

  use KsefHubWeb, :live_view

  alias KsefHub.Exports
  alias KsefHub.Exports.ExportBatch
  alias KsefHub.Repo

  @impl true
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

  @impl true
  def handle_event("preview", _params, socket) do
    company = socket.assigns.current_company

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

  @impl true
  def handle_event("export", _params, socket) do
    company = socket.assigns.current_company
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
          |> Enum.map_join(", ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Export failed: #{message}")}
    end
  end

  @impl true
  def handle_info({:export_status, batch_id, _status}, socket) do
    company = socket.assigns.current_company

    case Repo.get(ExportBatch, batch_id) do
      nil ->
        {:noreply, socket}

      batch ->
        if batch.company_id == company.id do
          {:noreply, stream_insert(socket, :batches, batch)}
        else
          {:noreply, socket}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Exports
      <:subtitle>Download batches of invoices as ZIP files with PDF and CSV summary</:subtitle>
    </.header>

    <div class="mt-6 grid grid-cols-1 lg:grid-cols-3 gap-6">
      <%!-- New Export Form --%>
      <div class="card bg-base-100 border border-base-300 lg:col-span-1">
        <div class="card-body">
          <h2 class="card-title text-base">New Export</h2>

          <form phx-change="update_form" phx-submit="export" class="space-y-4">
            <div class="form-control">
              <label class="label"><span class="label-text">From</span></label>
              <input
                type="date"
                name="date_from"
                value={@date_from}
                class="input input-bordered w-full"
              />
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">To</span></label>
              <input
                type="date"
                name="date_to"
                value={@date_to}
                class="input input-bordered w-full"
              />
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Invoice Type</span></label>
              <select name="invoice_type" class="select select-bordered w-full">
                <option value="expense" selected={@invoice_type == "expense"}>Expenses</option>
                <option value="income" selected={@invoice_type == "income"}>Income</option>
                <option value="" selected={@invoice_type == ""}>All</option>
              </select>
            </div>

            <div class="form-control">
              <label class="label cursor-pointer justify-start gap-2">
                <input type="hidden" name="only_new" value="false" />
                <input
                  type="checkbox"
                  name="only_new"
                  value="true"
                  checked={@only_new}
                  class="checkbox checkbox-sm"
                />
                <span class="label-text">Only new invoices (not previously exported by me)</span>
              </label>
            </div>

            <div :if={@preview_count != nil} class="alert alert-info text-sm">
              <.icon name="hero-information-circle" class="size-5" />
              <span>
                {@preview_count} invoice{if @preview_count != 1, do: "s"} match{if @preview_count ==
                                                                                     1,
                                                                                   do: "es"} your filters.
              </span>
            </div>

            <div class="flex gap-2">
              <button type="button" phx-click="preview" class="btn btn-outline btn-sm flex-1">
                <.icon name="hero-eye" class="size-4" /> Preview
              </button>
              <button type="submit" class="btn btn-primary btn-sm flex-1">
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
            class="card bg-base-100 border border-base-300"
          >
            <div class="card-body p-4 flex flex-row items-center justify-between gap-4">
              <div class="flex-1 min-w-0">
                <div class="font-medium text-sm">
                  {batch.date_from} &mdash; {batch.date_to}
                  <span :if={batch.invoice_type} class="badge badge-sm badge-outline ml-1">
                    {batch.invoice_type}
                  </span>
                  <span :if={batch.only_new} class="badge badge-sm badge-outline ml-1">
                    new only
                  </span>
                </div>
                <div class="text-xs text-base-content/60 mt-0.5">
                  {format_datetime(batch.inserted_at)}
                  <span :if={batch.invoice_count}>
                    &middot; {batch.invoice_count} invoices
                  </span>
                </div>
                <div
                  :if={batch.status == :failed && batch.error_message}
                  class="text-xs text-error mt-1 truncate"
                >
                  {batch.error_message}
                </div>
              </div>

              <div class="flex-shrink-0">
                <span
                  :if={batch.status in [:pending, :processing]}
                  class="badge badge-info gap-1"
                >
                  <span class="loading loading-spinner loading-xs"></span> Processing
                </span>
                <.link
                  :if={batch.status == :completed}
                  href={~p"/exports/#{batch.id}/download"}
                  class="btn btn-success btn-sm gap-1"
                >
                  <.icon name="hero-arrow-down-tray" class="size-4" /> Download ZIP
                </.link>
                <span :if={batch.status == :failed} class="badge badge-error">
                  Failed
                </span>
              </div>
            </div>
          </div>
        </div>

        <div :if={@batches_count == 0} class="text-center py-12">
          <.icon
            name="hero-arrow-down-tray"
            class="size-8 text-base-content/20 mx-auto mb-2"
          />
          <p class="text-base-content/60">
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
