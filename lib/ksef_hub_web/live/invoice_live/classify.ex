defmodule KsefHubWeb.InvoiceLive.Classify do
  @moduledoc """
  LiveView for the dedicated invoice categorization page.

  Presents category groups as collapsible accordion sections and tags as
  checkboxes. Saves classification atomically via `Invoices.with_manual_prediction/2`.
  """
  use KsefHubWeb, :live_view

  import KsefHubWeb.InvoiceComponents, only: [prediction_hint: 1]

  alias KsefHub.Authorization
  alias KsefHub.InvoiceClassifier
  alias KsefHub.Invoices
  alias KsefHub.Invoices.{CostLine, Invoice}

  # --- Mount ---

  @doc "Loads invoice, categories, tags, and permissions."
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(%{"id" => id}, _session, socket) do
    company = socket.assigns[:current_company]
    role = socket.assigns[:current_role]

    cond do
      !socket.assigns[:current_user] ->
        {:ok,
         socket
         |> put_flash(:error, "You must be logged in.")
         |> redirect(to: ~p"/")}

      !company ->
        {:ok,
         socket
         |> put_flash(:error, "No company selected.")
         |> redirect(to: ~p"/companies")}

      true ->
        case Invoices.get_invoice_with_details(company.id, id,
               role: role,
               user_id: socket.assigns.current_user.id
             ) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "Invoice not found.")
             |> redirect(to: ~p"/c/#{company.id}/invoices")}

          invoice ->
            mount_invoice(socket, invoice, role, company)
        end
    end
  end

  @spec mount_invoice(Phoenix.LiveView.Socket.t(), map(), atom(), map()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  defp mount_invoice(socket, invoice, role, company) do
    can_set_category =
      invoice.type == :expense && Authorization.can?(role, :set_invoice_category)

    can_set_tags = Authorization.can?(role, :set_invoice_tags)

    categories = Invoices.list_categories(company.id)
    grouped = group_categories(categories)

    distinct_tags =
      Invoices.list_distinct_tags(company.id, invoice.type,
        role: socket.assigns[:current_role],
        user_id: socket.assigns[:current_user] && socket.assigns.current_user.id
      )

    current_tags = MapSet.new(invoice.tags)
    # Merge invoice's own tags into the list so they always appear as checkboxes.
    # Preserves recency order from list_distinct_tags, appending any missing invoice tags at the end.
    all_tags = Enum.uniq(distinct_tags ++ invoice.tags)
    project_tags = Invoices.list_project_tags(company.id)

    category_cost_line_map =
      Map.new(categories, fn c -> {c.id, c.default_cost_line} end)

    {cat_threshold, tag_threshold} = InvoiceClassifier.thresholds_for_company(company.id)

    {:ok,
     socket
     |> assign(
       page_title: "Classify #{invoice.invoice_number}",
       invoice: invoice,
       categories: categories,
       grouped_categories: grouped,
       all_tags: all_tags,
       selected_category_id: invoice.expense_category_id,
       selected_tags: current_tags,
       selected_cost_line: invoice.expense_cost_line,
       selected_project_tag: invoice.project_tag,
       project_tags: project_tags,
       category_cost_line_map: category_cost_line_map,
       can_set_category: can_set_category,
       can_set_tags: can_set_tags,
       new_tag_form: to_form(%{"name" => ""}),
       new_project_tag_form: to_form(%{"name" => ""}),
       tag_form_key: 0,
       project_tag_form_key: 0,
       show_all_tags: false,
       show_all_project_tags: false,
       category_confidence_threshold: cat_threshold,
       tag_confidence_threshold: tag_threshold,
       expanded_group: expanded_group_for(invoice.expense_category_id, categories)
     )}
  end

  # --- Events ---

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("select_category", %{"id" => id}, socket) do
    if socket.assigns.can_set_category do
      category_id = if id == "", do: nil, else: id

      # Auto-update cost_line from category's default (only when selecting, not clearing)
      selected_cost_line =
        if category_id do
          default = socket.assigns.category_cost_line_map[category_id]
          default || socket.assigns.selected_cost_line
        else
          socket.assigns.selected_cost_line
        end

      {:noreply,
       assign(socket,
         selected_category_id: category_id,
         selected_cost_line: selected_cost_line,
         expanded_group: expanded_group_for(category_id, socket.assigns.categories)
       )}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to set categories.")}
    end
  end

  def handle_event("toggle_group", %{"group" => group}, socket) do
    current = socket.assigns.expanded_group

    {:noreply, assign(socket, :expanded_group, if(current == group, do: nil, else: group))}
  end

  def handle_event("select_cost_line", %{"expense_cost_line" => value}, socket) do
    if socket.assigns.can_set_category do
      case CostLine.cast(value) do
        {:ok, cost_line} -> {:noreply, assign(socket, :selected_cost_line, cost_line)}
        :error -> {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to set cost line.")}
    end
  end

  def handle_event("toggle_tag", %{"tag-name" => tag_name}, socket) do
    if socket.assigns.can_set_tags do
      current = socket.assigns.selected_tags

      updated =
        if MapSet.member?(current, tag_name),
          do: MapSet.delete(current, tag_name),
          else: MapSet.put(current, tag_name)

      {:noreply, assign(socket, :selected_tags, updated)}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to manage tags.")}
    end
  end

  def handle_event("toggle_show_all_tags", _params, socket) do
    {:noreply, assign(socket, :show_all_tags, !socket.assigns.show_all_tags)}
  end

  def handle_event("toggle_show_all_project_tags", _params, socket) do
    {:noreply, assign(socket, :show_all_project_tags, !socket.assigns.show_all_project_tags)}
  end

  def handle_event("select_project_tag", %{"value" => value}, socket) do
    if socket.assigns.can_set_tags do
      tag = if value == "", do: nil, else: value
      {:noreply, assign(socket, :selected_project_tag, tag)}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to set project tags.")}
    end
  end

  def handle_event("set_custom_project_tag", %{"name" => name}, socket) do
    if socket.assigns.can_set_tags do
      apply_custom_project_tag(socket, String.trim(name))
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to set project tags.")}
    end
  end

  def handle_event("create_tag", %{"name" => name}, socket) do
    if socket.assigns.can_set_tags do
      create_tag(socket, name)
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to manage tags.")}
    end
  end

  def handle_event("save", _params, socket) do
    if socket.assigns.can_set_category or socket.assigns.can_set_tags do
      save_classification(socket)
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to classify invoices.")}
    end
  end

  def handle_event("cancel", _params, socket) do
    company = socket.assigns.current_company
    invoice = socket.assigns.invoice

    {:noreply, push_navigate(socket, to: ~p"/c/#{company.id}/invoices/#{invoice.id}")}
  end

  # --- Private event helpers ---

  @spec create_tag(Phoenix.LiveView.Socket.t(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp create_tag(socket, name) do
    case String.trim(name) do
      "" ->
        {:noreply, socket}

      trimmed ->
        all_tags =
          if trimmed in socket.assigns.all_tags,
            do: socket.assigns.all_tags,
            else: [trimmed | socket.assigns.all_tags]

        {:noreply,
         socket
         |> assign(
           all_tags: all_tags,
           selected_tags: MapSet.put(socket.assigns.selected_tags, trimmed),
           new_tag_form: to_form(%{"name" => ""}),
           tag_form_key: socket.assigns.tag_form_key + 1
         )}
    end
  end

  @spec save_classification(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp save_classification(socket) do
    invoice = socket.assigns.invoice
    category_id = socket.assigns.selected_category_id
    tag_names = MapSet.to_list(socket.assigns.selected_tags)

    can_set_category = socket.assigns.can_set_category
    can_set_tags = socket.assigns.can_set_tags
    company = socket.assigns.current_company

    cost_line = socket.assigns.selected_cost_line
    project_tag = socket.assigns.selected_project_tag

    opts = actor_opts(socket)

    result =
      Invoices.with_manual_prediction(invoice, fn ->
        with {:ok, updated} <-
               maybe_set_category_and_cost_line(
                 invoice,
                 category_id,
                 cost_line,
                 can_set_category,
                 opts
               ),
             {:ok, updated} <- maybe_set_tags(updated, tag_names, can_set_tags, opts) do
          maybe_set_project_tag(updated, project_tag, can_set_tags, opts)
        end
      end)

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Classification saved.")
         |> push_navigate(to: ~p"/c/#{company.id}/invoices/#{invoice.id}")}

      {:error, :expense_only} ->
        {:noreply,
         put_flash(socket, :error, "Categories can only be assigned to expense invoices.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save classification.")}
    end
  end

  @spec maybe_set_category_and_cost_line(
          KsefHub.Invoices.Invoice.t(),
          Ecto.UUID.t() | nil,
          atom() | nil,
          boolean(),
          keyword()
        ) :: {:ok, KsefHub.Invoices.Invoice.t()} | {:error, term()}
  defp maybe_set_category_and_cost_line(invoice, _category_id, _cost_line, false, _opts),
    do: {:ok, invoice}

  defp maybe_set_category_and_cost_line(invoice, category_id, cost_line, true, opts) do
    with {:ok, updated} <- Invoices.set_invoice_category(invoice, category_id, opts) do
      Invoices.set_invoice_cost_line(updated, cost_line, opts)
    end
  end

  @spec maybe_set_tags(Invoice.t(), [String.t()], boolean(), keyword()) ::
          {:ok, Invoice.t()} | {:error, term()}
  defp maybe_set_tags(invoice, _tags, false, _opts), do: {:ok, invoice}

  defp maybe_set_tags(invoice, tags, true, opts),
    do: Invoices.set_invoice_tags(invoice, tags, opts)

  @spec apply_custom_project_tag(Phoenix.LiveView.Socket.t(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp apply_custom_project_tag(socket, ""), do: {:noreply, socket}

  defp apply_custom_project_tag(socket, trimmed) do
    project_tags =
      if trimmed in socket.assigns.project_tags,
        do: socket.assigns.project_tags,
        else: [trimmed | socket.assigns.project_tags]

    {:noreply,
     socket
     |> assign(
       selected_project_tag: trimmed,
       project_tags: project_tags,
       new_project_tag_form: to_form(%{"name" => ""}),
       project_tag_form_key: socket.assigns.project_tag_form_key + 1
     )}
  end

  @spec maybe_set_project_tag(Invoice.t(), String.t() | nil, boolean(), keyword()) ::
          {:ok, Invoice.t()} | {:error, term()}
  defp maybe_set_project_tag(invoice, _project_tag, false, _opts), do: {:ok, invoice}

  defp maybe_set_project_tag(invoice, project_tag, true, opts),
    do: Invoices.set_invoice_project_tag(invoice, project_tag, opts)

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-6 px-4">
      <nav class="text-sm text-muted-foreground mb-4">
        <.link navigate={~p"/c/#{@current_company.id}/invoices"} class="hover:underline">
          Invoices
        </.link>
        <span class="mx-1">/</span>
        <.link
          navigate={~p"/c/#{@current_company.id}/invoices/#{@invoice.id}"}
          class="hover:underline"
        >
          {@invoice.invoice_number}
        </.link>
        <span class="mx-1">/</span>
        <span>Classify</span>
      </nav>

      <h1 class="text-xl font-bold mb-6">Classification</h1>

      <%!-- Category Section --%>
      <section :if={@can_set_category} class="mb-8" data-testid="category-section">
        <h2 class="text-base font-semibold mb-3">Category</h2>
        <p class="text-xs text-muted-foreground mb-3">
          Classify the invoice into an accounting category for reporting and cost analysis.
        </p>

        <%!-- Clear category option --%>
        <button
          :if={@selected_category_id}
          phx-click="select_category"
          phx-value-id=""
          class="text-xs text-muted-foreground hover:text-foreground mb-3 underline-offset-4 hover:underline"
          data-testid="clear-category"
        >
          Clear category
        </button>

        <%!-- Accordion groups --%>
        <div class="space-y-1">
          <div :for={{group, cats} <- @grouped_categories} class="border border-border rounded-lg">
            <button
              phx-click="toggle_group"
              phx-value-group={group}
              class="w-full flex items-center justify-between px-3 py-2 text-sm font-medium hover:bg-muted rounded-lg"
              data-testid={"group-#{group}"}
            >
              <span class="capitalize">{group}</span>
              <.icon
                name={
                  if @expanded_group == group,
                    do: "hero-chevron-up",
                    else: "hero-chevron-down"
                }
                class="size-4"
              />
            </button>
            <div
              :if={@expanded_group == group}
              class="px-2 pb-2 space-y-0.5"
              data-testid={"group-items-#{group}"}
            >
              <button
                :for={cat <- cats}
                phx-click="select_category"
                phx-value-id={cat.id}
                class={[
                  "w-full text-left px-3 py-2 rounded-md text-sm flex items-center gap-2 transition-colors",
                  if(@selected_category_id == cat.id,
                    do: "bg-shad-primary/10 text-shad-primary font-medium",
                    else: "hover:bg-muted"
                  )
                ]}
                data-testid={"category-#{cat.id}"}
              >
                <span :if={cat.emoji}>{cat.emoji}</span>
                <div>
                  <div>{cat.name || category_target(cat.identifier)}</div>
                  <div :if={cat.description} class="text-xs text-muted-foreground">
                    {cat.description}
                  </div>
                  <div :if={cat.examples} class="text-xs text-muted-foreground/70 mt-0.5">
                    {cat.examples}
                  </div>
                </div>
              </button>
            </div>
          </div>
        </div>

        <.prediction_hint
          predicted_at={@invoice.prediction_predicted_at}
          status={@invoice.prediction_status}
          confidence={@invoice.prediction_expense_category_confidence}
          threshold={@category_confidence_threshold}
          label="category"
          testid="prediction-category-hint"
        />
      </section>

      <%!-- Cost Line Section --%>
      <section :if={@can_set_category} class="mb-8" data-testid="cost-line-section">
        <h2 class="text-base font-semibold mb-3">Cost Line</h2>
        <p class="text-xs text-muted-foreground mb-3">
          Map the invoice to a cost line for budget tracking and financial reporting.
        </p>
        <form phx-change="select_cost_line">
          <select
            name="expense_cost_line"
            class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            data-testid="cost-line-select"
          >
            <option value="" selected={is_nil(@selected_cost_line)}>None</option>
            <option
              :for={{label, value} <- CostLine.options()}
              value={value}
              selected={@selected_cost_line == value}
            >
              {label}
            </option>
          </select>
        </form>
      </section>

      <%!-- Tags Section --%>
      <section :if={@can_set_tags} class="mb-8" data-testid="tags-section">
        <h2 class="text-base font-semibold mb-3">Tags</h2>
        <p class="text-xs text-muted-foreground mb-3">
          Add tags to organize invoices by topic, department, or any custom grouping.
        </p>

        <div class="space-y-1">
          <label
            :for={tag <- visible_tags(@all_tags, @selected_tags, @show_all_tags)}
            class="flex items-center gap-2 cursor-pointer hover:bg-muted rounded px-2 py-1.5"
          >
            <input
              type="checkbox"
              class="size-3.5 rounded border border-input bg-background accent-shad-primary"
              checked={MapSet.member?(@selected_tags, tag)}
              phx-click="toggle_tag"
              phx-value-tag-name={tag}
            />
            <span class="text-sm">{tag}</span>
          </label>
        </div>

        <% hidden_count = hidden_tag_count(@all_tags, @selected_tags) %>
        <button
          :if={hidden_count > 0 or @show_all_tags}
          phx-click="toggle_show_all_tags"
          class="text-xs text-muted-foreground hover:text-foreground mt-2 underline-offset-4 hover:underline"
          data-testid="toggle-show-all-tags"
        >
          {if @show_all_tags, do: "Show less", else: "Show more (#{hidden_count} more)"}
        </button>

        <.prediction_hint
          predicted_at={@invoice.prediction_predicted_at}
          status={@invoice.prediction_status}
          confidence={@invoice.prediction_expense_tag_confidence}
          threshold={@tag_confidence_threshold}
          label="tag"
          testid="prediction-tag-hint"
        />

        <%!-- New Tag Inline --%>
        <.form
          :if={@can_set_tags}
          for={@new_tag_form}
          phx-submit="create_tag"
          id={"new-tag-form-#{@tag_form_key}"}
          class="flex gap-2 mt-3"
        >
          <input
            type="text"
            name={@new_tag_form[:name].name}
            value={@new_tag_form[:name].value}
            placeholder="New tag..."
            class="h-8 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring flex-1"
            data-testid="new-tag-input"
          />
          <.button type="submit" size="sm">Add</.button>
        </.form>
      </section>

      <%!-- Project Tag Section --%>
      <section :if={@can_set_tags} class="mb-8" data-testid="project-tag-section">
        <h2 class="text-base font-semibold mb-3">Project Tag</h2>
        <p class="text-xs text-muted-foreground mb-3">
          Assign the invoice to a project for expense allocation and project tracking.
        </p>

        <div class="space-y-1">
          <label class="flex items-center gap-2 cursor-pointer hover:bg-muted rounded px-2 py-1.5">
            <input
              type="radio"
              name="project_tag"
              value=""
              checked={is_nil(@selected_project_tag)}
              phx-click="select_project_tag"
              phx-value-value=""
              class="size-3.5 accent-shad-primary"
            />
            <span class="text-sm text-muted-foreground">None</span>
          </label>

          <label
            :for={
              tag <-
                visible_project_tags(@project_tags, @selected_project_tag, @show_all_project_tags)
            }
            class="flex items-center gap-2 cursor-pointer hover:bg-muted rounded px-2 py-1.5"
          >
            <input
              type="radio"
              name="project_tag"
              value={tag}
              checked={@selected_project_tag == tag}
              phx-click="select_project_tag"
              phx-value-value={tag}
              class="size-3.5 accent-shad-primary"
            />
            <span class="text-sm">{tag}</span>
          </label>
        </div>

        <% hidden_count = hidden_project_tag_count(@project_tags, @selected_project_tag) %>
        <button
          :if={hidden_count > 0 or @show_all_project_tags}
          phx-click="toggle_show_all_project_tags"
          class="text-xs text-muted-foreground hover:text-foreground mt-2 underline-offset-4 hover:underline"
          data-testid="toggle-show-all-project-tags"
        >
          {if @show_all_project_tags, do: "Show less", else: "Show more (#{hidden_count} more)"}
        </button>

        <.form
          :if={@can_set_tags}
          for={@new_project_tag_form}
          phx-submit="set_custom_project_tag"
          id={"new-project-tag-form-#{@project_tag_form_key}"}
          class="flex gap-2 mt-3"
        >
          <input
            type="text"
            name={@new_project_tag_form[:name].name}
            value={@new_project_tag_form[:name].value}
            placeholder="Custom project tag..."
            class="h-8 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring flex-1"
            data-testid="new-project-tag-input"
          />
          <.button type="submit" size="sm">Set</.button>
        </.form>
      </section>

      <%!-- Actions --%>
      <div class="flex gap-3">
        <.button phx-click="save" data-testid="save-classification">Save</.button>
        <.button variant="outline" phx-click="cancel">Cancel</.button>
      </div>
    </div>
    """
  end

  # --- Function Components ---

  # --- Private ---

  @spec group_categories([map()]) :: [{String.t(), [map()]}]
  defp group_categories(categories) do
    categories
    |> Enum.group_by(&category_group/1)
    |> Enum.sort_by(fn {_group, cats} -> Enum.min_by(cats, & &1.sort_order).sort_order end)
  end

  @spec category_group(map()) :: String.t()
  defp category_group(%{identifier: identifier}) do
    case String.split(identifier, ":", parts: 2) do
      [group, _target] -> group
      [identifier] -> identifier
    end
  end

  @spec category_target(String.t()) :: String.t()
  defp category_target(identifier) do
    case String.split(identifier, ":", parts: 2) do
      [_group, target] -> target
      [identifier] -> identifier
    end
  end

  @spec expanded_group_for(String.t() | nil, [map()]) :: String.t() | nil
  defp expanded_group_for(nil, _categories), do: nil

  defp expanded_group_for(category_id, categories) do
    case Enum.find(categories, &(&1.id == category_id)) do
      nil -> nil
      cat -> category_group(cat)
    end
  end

  @default_visible_limit 8

  @spec visible_tags([String.t()], MapSet.t(), boolean()) :: [String.t()]
  defp visible_tags(all_tags, selected_tags, show_all) do
    visible_items(all_tags, show_all, &MapSet.member?(selected_tags, &1))
  end

  @spec hidden_tag_count([String.t()], MapSet.t()) :: non_neg_integer()
  defp hidden_tag_count(all_tags, selected_tags) do
    hidden_item_count(all_tags, &MapSet.member?(selected_tags, &1))
  end

  @spec visible_project_tags([String.t()], String.t() | nil, boolean()) :: [String.t()]
  defp visible_project_tags(all_tags, selected, show_all) do
    visible_items(all_tags, show_all, &(&1 == selected))
  end

  @spec hidden_project_tag_count([String.t()], String.t() | nil) :: non_neg_integer()
  defp hidden_project_tag_count(all_tags, selected) do
    hidden_item_count(all_tags, &(&1 == selected))
  end

  @spec visible_items(list(), boolean(), (any() -> boolean())) :: list()
  defp visible_items(all_items, true, _selected?), do: all_items

  defp visible_items(all_items, false, selected?) do
    {top, rest} = Enum.split(all_items, @default_visible_limit)
    top ++ Enum.filter(rest, selected?)
  end

  @spec hidden_item_count(list(), (any() -> boolean())) :: non_neg_integer()
  defp hidden_item_count(all_items, selected?) do
    all_items
    |> Enum.drop(@default_visible_limit)
    |> Enum.count(&(not selected?.(&1)))
  end
end
