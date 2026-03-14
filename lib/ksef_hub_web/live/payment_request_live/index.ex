defmodule KsefHubWeb.PaymentRequestLive.Index do
  @moduledoc """
  LiveView for listing, filtering, and bulk-managing payment requests with pagination.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Authorization
  alias KsefHub.PaymentRequests
  alias KsefHub.PaymentRequests.PaymentRequest

  import KsefHubWeb.InvoiceComponents,
    only: [format_amount: 1, format_datetime: 1]

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Payment Requests",
       selected_ids: MapSet.new()
     )}
  end

  @impl true
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

    {:noreply,
     assign(socket,
       payment_requests: result.entries,
       filters: filters,
       form: form,
       page: result.page,
       per_page: result.per_page,
       total_count: result.total_count,
       total_pages: result.total_pages,
       can_manage: can_manage,
       selected_ids: MapSet.new()
     )}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("filter", %{"filters" => params}, socket) do
    query_params =
      %{}
      |> maybe_put("status", params["status"])
      |> maybe_put("date_from", params["date_from"])
      |> maybe_put("date_to", params["date_to"])
      |> maybe_put("query", params["query"])

    company_id = socket.assigns.current_company.id
    {:noreply, push_patch(socket, to: ~p"/c/#{company_id}/payment-requests?#{query_params}")}
  end

  def handle_event("clear_filters", _params, socket) do
    company_id = socket.assigns.current_company.id
    {:noreply, push_patch(socket, to: ~p"/c/#{company_id}/payment-requests")}
  end

  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_ids, id) do
        MapSet.delete(socket.assigns.selected_ids, id)
      else
        MapSet.put(socket.assigns.selected_ids, id)
      end

    {:noreply, assign(socket, selected_ids: selected)}
  end

  def handle_event("toggle_select_all", _params, socket) do
    all_ids = MapSet.new(socket.assigns.payment_requests, & &1.id)

    selected =
      if MapSet.equal?(socket.assigns.selected_ids, all_ids) do
        MapSet.new()
      else
        all_ids
      end

    {:noreply, assign(socket, selected_ids: selected)}
  end

  def handle_event("mark_paid", _params, socket) do
    if Authorization.can?(socket.assigns[:current_role], :manage_payment_requests) do
      company_id = socket.assigns.current_company.id
      ids = MapSet.to_list(socket.assigns.selected_ids)

      {count, _} = PaymentRequests.mark_many_as_paid(company_id, ids)

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
    company_id = socket.assigns.current_company.id
    ids = socket.assigns.selected_ids |> MapSet.to_list() |> Enum.join(",")

    {:noreply, redirect(socket, to: ~p"/c/#{company_id}/payment-requests/csv?ids=#{ids}")}
  end

  # --- Filter helpers ---

  @spec parse_filters(map()) :: map()
  defp parse_filters(params) do
    %{}
    |> maybe_put_enum(:status, params["status"], PaymentRequest, :status)
    |> maybe_put_date(:date_from, params["date_from"])
    |> maybe_put_date(:date_to, params["date_to"])
    |> maybe_put_search(:query, params["query"])
    |> maybe_put_page(:page, params["page"])
  end

  @spec build_filters_form(map()) :: Phoenix.HTML.Form.t()
  defp build_filters_form(filters) do
    %{
      "status" => to_string_or_empty(filters[:status]),
      "date_from" => (filters[:date_from] && Date.to_iso8601(filters[:date_from])) || "",
      "date_to" => (filters[:date_to] && Date.to_iso8601(filters[:date_to])) || "",
      "query" => filters[:query] || ""
    }
    |> to_form(as: :filters)
  end

  @spec filter_params_without_page(map()) :: map()
  defp filter_params_without_page(filters) do
    %{}
    |> maybe_put("status", to_string_or_empty(filters[:status]))
    |> maybe_put("date_from", filters[:date_from] && Date.to_iso8601(filters[:date_from]))
    |> maybe_put("date_to", filters[:date_to] && Date.to_iso8601(filters[:date_to]))
    |> maybe_put("query", filters[:query])
  end

  @spec maybe_put_enum(map(), atom(), String.t() | nil, module(), atom()) :: map()
  defp maybe_put_enum(map, _key, nil, _schema, _field), do: map
  defp maybe_put_enum(map, _key, "", _schema, _field), do: map

  defp maybe_put_enum(map, key, value, schema, field) do
    type = schema.__schema__(:type, field)

    case Ecto.Type.cast(type, value) do
      {:ok, atom} -> Map.put(map, key, atom)
      :error -> map
    end
  end

  @spec maybe_put_date(map(), atom(), String.t() | nil) :: map()
  defp maybe_put_date(map, _key, nil), do: map
  defp maybe_put_date(map, _key, ""), do: map

  defp maybe_put_date(map, key, value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> Map.put(map, key, date)
      _ -> map
    end
  end

  @spec maybe_put_search(map(), atom(), String.t() | nil) :: map()
  defp maybe_put_search(map, _key, nil), do: map
  defp maybe_put_search(map, _key, ""), do: map
  defp maybe_put_search(map, key, value), do: Map.put(map, key, value)

  @spec maybe_put_page(map(), atom(), String.t() | nil) :: map()
  defp maybe_put_page(map, _key, nil), do: map
  defp maybe_put_page(map, _key, ""), do: map

  defp maybe_put_page(map, key, value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> Map.put(map, key, int)
      _ -> map
    end
  end

  @spec maybe_put(map(), String.t(), String.t() | nil) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec to_string_or_empty(atom() | String.t() | nil) :: String.t()
  defp to_string_or_empty(nil), do: ""
  defp to_string_or_empty(value) when is_atom(value), do: Atom.to_string(value)
  defp to_string_or_empty(value) when is_binary(value), do: value

  @spec truncate_iban(String.t() | nil) :: String.t()
  defp truncate_iban(nil), do: "-"
  defp truncate_iban(""), do: "-"

  defp truncate_iban(iban) when byte_size(iban) > 10 do
    String.slice(iban, 0, 10) <> "..."
  end

  defp truncate_iban(iban), do: iban

  @spec status_variant(atom()) :: String.t()
  defp status_variant(:pending), do: "warning"
  defp status_variant(:paid), do: "success"
  defp status_variant(_), do: "muted"

  @impl true
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

    <.form for={@form} phx-change="filter" class="contents">
      <.filter_bar
        active_filters={[]}
        filter_count={0}
        search_name={@form[:query].name}
        search_value={@form[:query].value}
        search_placeholder="Recipient, title, IBAN..."
      >
        <:filter_fields>
          <div class="space-y-1">
            <label class="block text-xs font-medium text-muted-foreground">Status</label>
            <select
              name={@form[:status].name}
              class="w-full h-9 rounded-md border border-input bg-background px-2 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            >
              <option value="">All</option>
              <option value="pending" selected={@form[:status].value == "pending"}>Pending</option>
              <option value="paid" selected={@form[:status].value == "paid"}>Paid</option>
            </select>
          </div>

          <div class="space-y-1">
            <label class="block text-xs font-medium text-muted-foreground">From</label>
            <input
              type="date"
              name={@form[:date_from].name}
              value={@form[:date_from].value}
              class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            />
          </div>

          <div class="space-y-1">
            <label class="block text-xs font-medium text-muted-foreground">To</label>
            <input
              type="date"
              name={@form[:date_to].name}
              value={@form[:date_to].value}
              class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            />
          </div>
        </:filter_fields>
      </.filter_bar>
    </.form>

    <!-- Bulk actions bar -->
    <div
      :if={MapSet.size(@selected_ids) > 0 && @can_manage}
      class="flex items-center gap-3 mb-4 p-3 rounded-md border border-border bg-muted/50"
    >
      <span class="text-sm text-muted-foreground">
        {MapSet.size(@selected_ids)} selected
      </span>
      <.button size="sm" variant="success" phx-click="mark_paid">
        <.icon name="hero-check-circle" class="size-4" /> Mark as paid
      </.button>
      <.button size="sm" variant="outline" phx-click="download_csv">
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
                        length(@payment_requests)
                  }
                />
              </th>
              <th class="text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide w-28">
                Date
              </th>
              <th class="text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
                Recipient
              </th>
              <th class="text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
                Title
              </th>
              <th class="text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide w-36 text-right">
                Amount
              </th>
              <th class="text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide w-36">
                IBAN
              </th>
              <th class="text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide w-28">
                Status
              </th>
              <th class="text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide w-28">
                Invoice
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
                  type="checkbox"
                  class="checkbox checkbox-sm"
                  phx-click="toggle_select"
                  phx-value-id={pr.id}
                  checked={MapSet.member?(@selected_ids, pr.id)}
                />
              </td>
              <td class="py-3.5 px-4">
                <span class="whitespace-nowrap">{format_datetime(pr.inserted_at)}</span>
              </td>
              <td class="py-3.5 px-4">{pr.recipient_name}</td>
              <td class="py-3.5 px-4">{pr.title}</td>
              <td class="py-3.5 px-4 text-right">
                <span class="font-mono">{format_amount(pr.amount)}</span>
                <span class="text-xs text-muted-foreground">{pr.currency}</span>
              </td>
              <td class="py-3.5 px-4">
                <span class="font-mono text-xs">{truncate_iban(pr.iban)}</span>
              </td>
              <td class="py-3.5 px-4">
                <.badge variant={status_variant(pr.status)}>{pr.status}</.badge>
              </td>
              <td class="py-3.5 px-4">
                <.link
                  :if={pr.invoice_id}
                  navigate={~p"/c/#{@current_company.id}/invoices/#{pr.invoice_id}"}
                  class="text-shad-primary underline-offset-4 hover:underline text-xs"
                >
                  View invoice
                </.link>
                <span :if={!pr.invoice_id} class="text-muted-foreground">-</span>
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
