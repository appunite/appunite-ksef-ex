defmodule KsefHubWeb.PaymentRequestLive.Index do
  @moduledoc """
  LiveView for listing, filtering, and bulk-managing payment requests with pagination.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Authorization
  alias KsefHub.PaymentRequests
  alias KsefHub.PaymentRequests.PaymentRequest

  import KsefHubWeb.InvoiceComponents,
    only: [format_amount: 1, local_datetime: 1]

  import KsefHubWeb.FilterHelpers

  @impl true
  @doc "Assigns page title on mount."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Payment Requests", open_filter: nil)}
  end

  @impl true
  @doc "Loads payment requests with filters and pagination from URL params."
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params)
    role = socket.assigns[:current_role]

    result =
      case socket.assigns[:current_company] do
        %{id: company_id} ->
          PaymentRequests.list_payment_requests_paginated(company_id, filters)

        _ ->
          %{entries: [], page: 1, per_page: 25, total_count: 0, total_pages: 1}
      end

    form = build_filters_form(filters)
    can_manage = Authorization.can?(role, :manage_payment_requests)

    filter_count =
      length(filters[:statuses] || []) +
        if(filters[:date_from], do: 1, else: 0) +
        if(filters[:date_to], do: 1, else: 0) +
        if(filters[:query] && String.trim(filters[:query]) != "", do: 1, else: 0)

    {:noreply,
     assign(socket,
       payment_requests: result.entries,
       filters: filters,
       form: form,
       filter_count: filter_count,
       page: result.page,
       per_page: result.per_page,
       total_count: result.total_count,
       total_pages: result.total_pages,
       can_manage: can_manage,
       selected_ids: MapSet.new()
     )}
  end

  @impl true
  @doc "Handles UI events: filtering, selection, bulk actions, and CSV export."
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("filter", %{"filters" => params}, socket) do
    query_params = build_query_params(socket.assigns.filters, params)
    company_id = socket.assigns.current_company.id
    {:noreply, push_patch(socket, to: ~p"/c/#{company_id}/payment-requests?#{query_params}")}
  end

  def handle_event("toggle_filter", %{"field" => field, "value" => value}, socket) do
    filters = toggle_filter_value(socket.assigns.filters, field, value)
    query_params = build_query_params(filters, %{})
    company_id = socket.assigns.current_company.id
    {:noreply, push_patch(socket, to: ~p"/c/#{company_id}/payment-requests?#{query_params}")}
  end

  def handle_event("open_filter", %{"id" => id}, socket) do
    current = socket.assigns.open_filter
    {:noreply, assign(socket, :open_filter, if(current == id, do: nil, else: id))}
  end

  def handle_event("close_filter", _params, socket) do
    {:noreply, assign(socket, :open_filter, nil)}
  end

  def handle_event("clear_filters", _params, socket) do
    company_id = socket.assigns.current_company.id
    {:noreply, push_patch(socket, to: ~p"/c/#{company_id}/payment-requests")}
  end

  def handle_event("toggle_select", %{"id" => id}, socket) do
    if socket.assigns.can_manage do
      normalized_id =
        case Ecto.UUID.cast(id) do
          {:ok, uuid} -> uuid
          :error -> id
        end

      pr = Enum.find(socket.assigns.payment_requests, &(&1.id == normalized_id))

      selected =
        cond do
          is_nil(pr) or not selectable?(pr) ->
            socket.assigns.selected_ids

          MapSet.member?(socket.assigns.selected_ids, normalized_id) ->
            MapSet.delete(socket.assigns.selected_ids, normalized_id)

          true ->
            MapSet.put(socket.assigns.selected_ids, normalized_id)
        end

      {:noreply, assign(socket, selected_ids: selected)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_select_all", _params, socket) do
    if socket.assigns.can_manage do
      selectable_ids =
        socket.assigns.payment_requests
        |> Enum.filter(&selectable?/1)
        |> MapSet.new(& &1.id)

      selected =
        if MapSet.equal?(socket.assigns.selected_ids, selectable_ids) do
          MapSet.new()
        else
          selectable_ids
        end

      {:noreply, assign(socket, selected_ids: selected)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("mark_paid", _params, socket) do
    if socket.assigns.can_manage do
      company_id = socket.assigns.current_company.id
      ids = MapSet.to_list(socket.assigns.selected_ids)

      {count, _} = PaymentRequests.mark_many_as_paid(company_id, ids, actor_opts(socket))

      {:noreply,
       socket
       |> put_flash(:info, "#{count} payment request(s) marked as paid.")
       |> push_patch(
         to:
           ~p"/c/#{company_id}/payment-requests?#{filter_params_without_page(socket.assigns.filters)}"
       )}
    else
      {:noreply,
       put_flash(socket, :error, "You do not have permission to manage payment requests.")}
    end
  end

  def handle_event("download_csv", _params, socket) do
    if socket.assigns.can_manage do
      company_id = socket.assigns.current_company.id
      ids = socket.assigns.selected_ids |> MapSet.to_list() |> Enum.join(",")
      url = ~p"/c/#{company_id}/payment-requests/csv?ids=#{ids}"

      {:noreply, push_event(socket, "download", %{url: url})}
    else
      {:noreply, socket}
    end
  end

  # --- Filter helpers ---

  @spec parse_filters(map()) :: map()
  defp parse_filters(params) do
    %{}
    |> maybe_put_csv(:statuses, params["statuses"],
      valid: ~w(pending paid voided),
      transform: &String.to_existing_atom/1
    )
    |> maybe_put_date(:date_from, params["date_from"])
    |> maybe_put_date(:date_to, params["date_to"])
    |> maybe_put_search(:query, params["query"])
    |> maybe_put_page(:page, params["page"])
  end

  @spec build_filters_form(map()) :: Phoenix.HTML.Form.t()
  defp build_filters_form(filters) do
    %{
      "date_from" => (filters[:date_from] && Date.to_iso8601(filters[:date_from])) || "",
      "date_to" => (filters[:date_to] && Date.to_iso8601(filters[:date_to])) || "",
      "query" => filters[:query] || ""
    }
    |> to_form(as: :filters)
  end

  @spec build_query_params(map(), map()) :: map()
  defp build_query_params(filters, form_params) do
    %{}
    |> maybe_put("statuses", join_list(filters[:statuses]))
    |> maybe_put("date_from", form_params["date_from"] || date_to_string(filters[:date_from]))
    |> maybe_put("date_to", form_params["date_to"] || date_to_string(filters[:date_to]))
    |> maybe_put("query", form_params["query"] || filters[:query])
  end

  @spec filter_params_without_page(map()) :: map()
  defp filter_params_without_page(filters) do
    build_query_params(filters, %{})
  end

  @spec selected_totals_text([PaymentRequest.t()], MapSet.t()) :: String.t()
  defp selected_totals_text(payment_requests, selected_ids) do
    payment_requests
    |> Enum.filter(&MapSet.member?(selected_ids, &1.id))
    |> Enum.group_by(& &1.currency)
    |> Enum.sort_by(fn {currency, _} -> currency end)
    |> Enum.map_join(", ", fn {currency, prs} ->
      total = Enum.reduce(prs, Decimal.new(0), &Decimal.add(&1.amount, &2))
      "#{format_amount(total)} #{currency}"
    end)
  end

  @spec selectable?(PaymentRequest.t()) :: boolean()
  defp selectable?(%{status: status}) when status in [:voided, :paid], do: false
  defp selectable?(_), do: true

  @spec status_variant(atom()) :: String.t()
  defp status_variant(:pending), do: "warning"
  defp status_variant(:paid), do: "success"
  defp status_variant(:voided), do: "error"
  defp status_variant(_), do: "muted"

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.header>
      Payment Requests
      <:subtitle>Payment requests for {@current_company.name}</:subtitle>
      <:actions>
        <.button :if={@can_manage} navigate={~p"/c/#{@current_company.id}/payment-requests/new"}>
          <.icon name="hero-plus" class="size-4" /> New payment request
        </.button>
      </:actions>
    </.header>

    <div class="space-y-2 mt-4 mb-6">
      <div class="flex items-center gap-2 flex-wrap">
        <.multi_select
          id="status-filter"
          label="Status"
          field="statuses"
          options={[{"Pending", "pending"}, {"Paid", "paid"}, {"Voided", "voided"}]}
          selected={Enum.map(@filters[:statuses] || [], &to_string/1)}
          open={@open_filter == "status-filter"}
        />

        <.form for={@form} id="pr-date-search-form" phx-change="filter" class="contents">
          <input
            type="date"
            name={@form[:date_from].name}
            value={@form[:date_from].value}
            placeholder="From"
            phx-debounce="300"
            class="h-8 rounded-md border border-input bg-background px-2 text-xs focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          />
          <span class="text-xs text-muted-foreground">&ndash;</span>
          <input
            type="date"
            name={@form[:date_to].name}
            value={@form[:date_to].value}
            placeholder="To"
            phx-debounce="300"
            class="h-8 rounded-md border border-input bg-background px-2 text-xs focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          />

          <button
            :if={@filter_count > 0}
            type="button"
            phx-click="clear_filters"
            class="text-xs text-muted-foreground hover:text-foreground cursor-pointer"
          >
            Reset
          </button>

          <div class="ml-auto w-64">
            <div class="relative">
              <.icon
                name="hero-magnifying-glass"
                class="absolute left-2.5 top-2 size-4 text-muted-foreground"
              />
              <input
                type="text"
                name={@form[:query].name}
                value={@form[:query].value}
                placeholder="Recipient, title, IBAN..."
                phx-debounce="300"
                class="w-full h-8 rounded-md border border-input bg-background pl-8 pr-3 text-xs focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
              />
            </div>
          </div>
        </.form>
      </div>
    </div>

    <!-- Bulk actions bar -->
    <div
      :if={MapSet.size(@selected_ids) > 0}
      class="flex items-center gap-3 mb-4 p-3 rounded-md border border-border bg-muted/50"
      data-testid="bulk-actions-bar"
    >
      <span class="text-sm font-medium">
        {MapSet.size(@selected_ids)} selected
      </span>
      <span class="text-sm text-muted-foreground font-mono">
        {selected_totals_text(@payment_requests, @selected_ids)}
      </span>
      <div class="flex-1" />
      <.button :if={@can_manage} size="sm" variant="success" phx-click="mark_paid">
        <.icon name="hero-check-circle" class="size-4" /> Mark as paid
      </.button>
      <.button :if={@can_manage} size="sm" variant="outline" phx-click="download_csv">
        <.icon name="hero-arrow-down-tray" class="size-4" /> Download CSV
      </.button>
    </div>

    <!-- Payment Requests Table -->
    <div class="rounded-lg border border-border overflow-hidden">
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b border-border">
              <th :if={@can_manage} class="py-3 px-4 w-10">
                <input
                  type="checkbox"
                  class="checkbox checkbox-sm"
                  phx-click="toggle_select_all"
                  checked={
                    MapSet.size(@selected_ids) > 0 &&
                      MapSet.size(@selected_ids) ==
                        Enum.count(@payment_requests, &selectable?/1)
                  }
                />
              </th>
              <th class="hidden lg:table-cell text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide w-36">
                Created
              </th>
              <th class="text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
                Recipient
              </th>
              <th class="hidden md:table-cell text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
                Title
              </th>
              <th class="text-right py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide w-32">
                Amount
              </th>
              <th class="text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide w-20">
                Status
              </th>
              <th class="hidden lg:table-cell text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide w-36">
                Paid
              </th>
            </tr>
          </thead>
          <tbody id="payment-requests">
            <tr
              :for={pr <- @payment_requests}
              id={"pr-#{pr.id}"}
              class="border-b border-border/50 hover:bg-muted/50 transition-colors"
            >
              <td :if={@can_manage} class="py-3.5 px-4">
                <input
                  :if={selectable?(pr)}
                  type="checkbox"
                  class="checkbox checkbox-sm"
                  phx-click="toggle_select"
                  phx-value-id={pr.id}
                  checked={MapSet.member?(@selected_ids, pr.id)}
                />
              </td>
              <td class="hidden lg:table-cell py-3.5 px-4">
                <span class="whitespace-nowrap">
                  <.local_datetime at={pr.inserted_at} id={"pr-created-#{pr.id}"} />
                </span>
              </td>
              <td class="py-3.5 px-4">
                <.link
                  :if={@can_manage}
                  navigate={~p"/c/#{@current_company.id}/payment-requests/#{pr.id}/edit"}
                  class="text-shad-primary underline-offset-4 hover:underline"
                >
                  {pr.recipient_name}
                </.link>
                <span :if={!@can_manage}>{pr.recipient_name}</span>
                <div class="text-xs text-muted-foreground md:hidden">{pr.title}</div>
              </td>
              <td class="hidden md:table-cell py-3.5 px-4">{pr.title}</td>
              <td class="py-3.5 px-4 text-right">
                <span class="font-mono">{format_amount(pr.amount)}</span>
                <span class="text-xs text-muted-foreground">{pr.currency}</span>
              </td>
              <td class="py-3.5 px-4">
                <.badge variant={status_variant(pr.status)}>{pr.status}</.badge>
              </td>
              <td class="hidden lg:table-cell py-3.5 px-4">
                <span :if={pr.paid_at} class="whitespace-nowrap text-xs">
                  <.local_datetime at={pr.paid_at} id={"pr-paid-#{pr.id}"} />
                </span>
                <span :if={!pr.paid_at} class="text-muted-foreground">-</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p
        :if={@payment_requests == [] && @total_count == 0}
        class="text-center text-muted-foreground py-8"
      >
        No payment requests found matching your filters.
      </p>

      <div class="border-t border-border px-4 py-3">
        <.pagination
          page={@page}
          per_page={@per_page}
          total_count={@total_count}
          total_pages={@total_pages}
          base_url={~p"/c/#{@current_company.id}/payment-requests"}
          params={filter_params_without_page(@filters)}
          noun="payment requests"
        />
      </div>
    </div>
    """
  end
end
