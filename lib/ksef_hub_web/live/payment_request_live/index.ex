defmodule KsefHubWeb.PaymentRequestLive.Index do
  @moduledoc """
  LiveView for listing, filtering, and bulk-managing payment requests with pagination.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Authorization
  alias KsefHub.PaymentRequests
  alias KsefHub.PaymentRequests.PaymentRequest

  import KsefHubWeb.InvoiceComponents,
    only: [format_amount: 1, format_date_short: 1, format_month: 1]

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

    {result, stats, tab_counts} =
      case socket.assigns[:current_company] do
        %{id: company_id} ->
          {
            PaymentRequests.list_payment_requests_paginated(company_id, filters),
            PaymentRequests.payment_request_stats(company_id),
            PaymentRequests.count_payment_requests_by_status(company_id)
          }

        _ ->
          empty = %{entries: [], page: 1, per_page: 25, total_count: 0, total_pages: 1}

          empty_stats = %{
            pending_count: 0,
            pending_pln: Decimal.new(0),
            sent_this_month_pln: Decimal.new(0)
          }

          empty_counts = %{all: 0, pending: 0, paid: 0, voided: 0}
          {empty, empty_stats, empty_counts}
      end

    form = build_filters_form(filters)
    can_manage = Authorization.can?(role, :manage_payment_requests)

    filter_count =
      if(filters[:date_from], do: 1, else: 0) +
        if(filters[:date_to], do: 1, else: 0) +
        if(filters[:query] && String.trim(filters[:query]) != "", do: 1, else: 0)

    {:noreply,
     assign(socket,
       payment_requests: result.entries,
       filters: filters,
       form: form,
       filter_count: filter_count,
       stats: stats,
       tab_counts: tab_counts,
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

  def handle_event("void", %{"id" => id}, socket) do
    if socket.assigns.can_manage do
      company_id = socket.assigns.current_company.id

      case PaymentRequests.void_payment_request(company_id, id, actor_opts(socket)) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Payment request voided.")
           |> push_patch(
             to:
               ~p"/c/#{company_id}/payment-requests?#{filter_params_without_page(socket.assigns.filters)}"
           )}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not void payment request.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selected_ids: MapSet.new())}
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
          is_nil(pr) ->
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
      selectable_ids = MapSet.new(socket.assigns.payment_requests, & &1.id)

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

  @spec markable_as_paid?(PaymentRequest.t()) :: boolean()
  defp markable_as_paid?(%{status: :pending}), do: true
  defp markable_as_paid?(_), do: false

  @spec status_variant(atom()) :: String.t()
  defp status_variant(:pending), do: "warning"
  defp status_variant(:paid), do: "success"
  defp status_variant(:voided), do: "error"
  defp status_variant(_), do: "muted"

  @spec status_label(atom()) :: String.t()
  defp status_label(:pending), do: "pending"
  defp status_label(:paid), do: "sent"
  defp status_label(:voided), do: "voided"
  defp status_label(other), do: to_string(other)

  @spec current_tab_id(map()) :: String.t()
  defp current_tab_id(%{statuses: [status]}), do: to_string(status)
  defp current_tab_id(_), do: "all"

  @spec tab_url(String.t(), map(), atom() | nil) :: String.t()
  defp tab_url(company_id, filters, nil) do
    params = build_query_params(Map.delete(filters, :statuses), %{})
    ~p"/c/#{company_id}/payment-requests?#{params}"
  end

  defp tab_url(company_id, filters, status) when is_atom(status) do
    params = build_query_params(Map.put(filters, :statuses, [status]), %{})
    ~p"/c/#{company_id}/payment-requests?#{params}"
  end

  @spec date_sub_label(atom()) :: String.t()
  defp date_sub_label(:voided), do: "VOIDED"
  defp date_sub_label(_), do: ""

  @spec pr_date(PaymentRequest.t()) :: Date.t()
  defp pr_date(%{status: :paid, paid_at: paid_at}) when not is_nil(paid_at),
    do: DateTime.to_date(paid_at)

  defp pr_date(%{status: :voided, voided_at: voided_at}) when not is_nil(voided_at),
    do: DateTime.to_date(voided_at)

  defp pr_date(%{inserted_at: %NaiveDateTime{} = dt}), do: NaiveDateTime.to_date(dt)
  defp pr_date(%{inserted_at: %DateTime{} = dt}), do: DateTime.to_date(dt)

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

    <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-5">
      <.card>
        <div class="text-xs text-muted-foreground uppercase tracking-wide">Pending Outflow</div>
        <div class="mt-1 text-2xl font-semibold tabular-nums">
          {format_amount(@stats.pending_pln)}
          <span class="text-sm font-mono text-muted-foreground ml-1.5">PLN</span>
        </div>
        <div class="text-xs text-muted-foreground mt-1">{@stats.pending_count} pending</div>
      </.card>
      <.card>
        <div class="text-xs text-muted-foreground uppercase tracking-wide">Pending Count</div>
        <div class="mt-1 text-2xl font-semibold tabular-nums">
          {@stats.pending_count}
        </div>
        <div class="text-xs text-muted-foreground mt-1">awaiting payment</div>
      </.card>
      <.card>
        <div class="text-xs text-muted-foreground uppercase tracking-wide">Sent This Month</div>
        <div class="mt-1 text-2xl font-semibold tabular-nums">
          {format_amount(@stats.sent_this_month_pln)}
          <span class="text-sm font-mono text-muted-foreground ml-1.5">PLN</span>
        </div>
        <div class="text-xs text-muted-foreground mt-1">{format_month(Date.utc_today())}</div>
      </.card>
    </div>

    <.status_tabs
      active_id={current_tab_id(@filters)}
      tabs={[
        %{
          id: "all",
          label: "All",
          count: @tab_counts.all,
          href: tab_url(@current_company.id, @filters, nil)
        },
        %{
          id: "pending",
          label: "Pending",
          count: @tab_counts.pending,
          href: tab_url(@current_company.id, @filters, :pending)
        },
        %{
          id: "paid",
          label: "Sent",
          count: @tab_counts.paid,
          href: tab_url(@current_company.id, @filters, :paid)
        },
        %{
          id: "voided",
          label: "Voided",
          count: @tab_counts.voided,
          href: tab_url(@current_company.id, @filters, :voided)
        }
      ]}
    />

    <div class="flex items-center gap-2 flex-wrap mb-4">
      <.form for={@form} id="pr-search-form" phx-change="filter" class="contents">
        <.search_input
          name={@form[:query].name}
          value={@form[:query].value}
          placeholder="Recipient, title, IBAN..."
          phx-debounce="300"
          class="w-48 lg:w-64"
        />
      </.form>
      <.form for={@form} id="pr-date-form" phx-change="filter" class="contents">
        <.date_range_picker
          id="pr-date-range"
          from_name={@form[:date_from].name}
          to_name={@form[:date_to].name}
          from_value={@form[:date_from].value}
          to_value={@form[:date_to].value}
        />
      </.form>
      <.reset_filters_button :if={@filter_count > 0} />
    </div>

    <div
      :if={MapSet.size(@selected_ids) > 0}
      class="flex items-center justify-between px-4 py-2.5 mb-0 rounded-t-lg bg-foreground text-background border border-border"
      data-testid="bulk-actions-bar"
    >
      <div class="flex items-center gap-3 text-sm">
        <span class="font-medium tabular-nums">{MapSet.size(@selected_ids)} selected</span>
        <span class="opacity-40">·</span>
        <span class="font-mono text-xs tabular-nums opacity-80">
          {selected_totals_text(@payment_requests, @selected_ids)}
        </span>
        <span class="opacity-40">·</span>
        <span class="text-xs opacity-70">
          {Enum.count(@payment_requests, fn pr ->
            MapSet.member?(@selected_ids, pr.id) && markable_as_paid?(pr)
          end)} of {MapSet.size(@selected_ids)} can be marked paid
        </span>
      </div>
      <div class="flex items-center gap-2">
        <button
          phx-click="clear_selection"
          class="h-7 px-2.5 text-xs rounded-md border border-background/30 hover:bg-background/10 transition-all"
        >
          Clear
        </button>
        <button
          :if={@can_manage}
          phx-click="download_csv"
          class="h-7 px-2.5 text-xs rounded-md border border-background/30 hover:bg-background/10 transition-all flex items-center gap-1.5"
        >
          <.icon name="hero-arrow-down-tray" class="size-3.5" /> Download CSV
        </button>
        <button
          :if={@can_manage}
          phx-click="mark_paid"
          class="h-7 px-2.5 text-xs rounded-md bg-background/20 border border-background/30 hover:bg-background/30 transition-all flex items-center gap-1.5"
        >
          <.icon name="hero-check-circle" class="size-3.5" /> Mark as paid
        </button>
      </div>
    </div>

    <.table_container class={MapSet.size(@selected_ids) > 0 && "rounded-t-none border-t-0"}>
      <table class="w-full text-sm">
        <thead class="bg-muted/50 border-b border-border">
          <tr>
            <th :if={@can_manage} class="py-2.5 px-4 w-10">
              <input
                type="checkbox"
                class="checkbox checkbox-sm"
                phx-click="toggle_select_all"
                checked={
                  MapSet.size(@selected_ids) > 0 &&
                    MapSet.size(@selected_ids) == length(@payment_requests)
                }
              />
            </th>
            <th class="text-left py-2.5 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
              Counterparty
            </th>
            <th class="hidden md:table-cell text-left py-2.5 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
              Invoice
            </th>
            <th class="hidden md:table-cell text-left py-2.5 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
              Reference
            </th>
            <th class="text-right py-2.5 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
              Amount
            </th>
            <th class="hidden lg:table-cell text-left py-2.5 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
              Date
            </th>
            <th class="text-left py-2.5 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
              Status
            </th>
            <th class="w-0 py-2.5 pr-3 pl-0"></th>
          </tr>
        </thead>
        <tbody id="payment-requests">
          <tr
            :for={pr <- @payment_requests}
            id={"pr-#{pr.id}"}
            class={[
              "group border-b border-border hover:bg-shad-accent transition-colors",
              @can_manage && "cursor-pointer"
            ]}
          >
            <td :if={@can_manage} class="py-3 px-4" onclick="event.stopPropagation()">
              <input
                type="checkbox"
                class="checkbox checkbox-sm"
                phx-click="toggle_select"
                phx-value-id={pr.id}
                checked={MapSet.member?(@selected_ids, pr.id)}
              />
            </td>
            <td
              class="py-3 px-4"
              phx-click={
                if @can_manage,
                  do: JS.navigate(~p"/c/#{@current_company.id}/payment-requests/#{pr.id}/edit")
              }
            >
              <div class={["text-sm truncate", pr.status == :voided && "line-through opacity-60"]}>
                {pr.recipient_name}
              </div>
              <div class="font-mono text-[11px] text-muted-foreground truncate">{pr.iban}</div>
            </td>
            <td
              class="hidden md:table-cell py-3 px-4"
              phx-click={
                if @can_manage,
                  do: JS.navigate(~p"/c/#{@current_company.id}/payment-requests/#{pr.id}/edit")
              }
            >
              <span :if={pr.invoice} class="font-mono text-xs tabular-nums truncate block">
                {pr.invoice.invoice_number}
              </span>
              <span :if={!pr.invoice} class="text-muted-foreground">-</span>
            </td>
            <td
              class="hidden md:table-cell py-3 px-4"
              phx-click={
                if @can_manage,
                  do: JS.navigate(~p"/c/#{@current_company.id}/payment-requests/#{pr.id}/edit")
              }
            >
              <span class={[
                "text-sm text-muted-foreground truncate block",
                pr.status == :voided && "line-through opacity-60"
              ]}>
                {pr.title}
              </span>
            </td>
            <td
              class="py-3 px-4 text-right whitespace-nowrap"
              phx-click={
                if @can_manage,
                  do: JS.navigate(~p"/c/#{@current_company.id}/payment-requests/#{pr.id}/edit")
              }
            >
              <span class={[
                "font-mono text-sm tabular-nums",
                pr.status == :voided && "line-through opacity-60"
              ]}>
                {format_amount(pr.amount)}
              </span>
              <span class="text-xs text-muted-foreground ml-1">{pr.currency}</span>
            </td>
            <td
              class="hidden lg:table-cell py-3 px-4"
              phx-click={
                if @can_manage,
                  do: JS.navigate(~p"/c/#{@current_company.id}/payment-requests/#{pr.id}/edit")
              }
            >
              <div class="font-mono text-xs tabular-nums text-muted-foreground whitespace-nowrap">
                {format_date_short(pr_date(pr))}
              </div>
              <div :if={date_sub_label(pr.status) != ""} class="text-[10px] text-muted-foreground">
                {date_sub_label(pr.status)}
              </div>
            </td>
            <td
              class="py-3 px-4"
              phx-click={
                if @can_manage,
                  do: JS.navigate(~p"/c/#{@current_company.id}/payment-requests/#{pr.id}/edit")
              }
            >
              <.badge variant={status_variant(pr.status)}>{status_label(pr.status)}</.badge>
            </td>
            <td class="w-0 py-3 pr-3 pl-0" onclick="event.stopPropagation()">
              <div class="flex items-center gap-1">
                <.button
                  :if={pr.status == :pending && @can_manage}
                  size="sm"
                  variant="ghost"
                  phx-click="void"
                  phx-value-id={pr.id}
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </.button>
                <.icon
                  name="hero-chevron-right"
                  class="size-3.5 text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity"
                />
              </div>
            </td>
          </tr>
        </tbody>
      </table>

      <.empty_state :if={@payment_requests == [] && @total_count == 0}>
        No data for selected period
      </.empty_state>

      <div class="px-4 py-3">
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
    </.table_container>
    """
  end
end
