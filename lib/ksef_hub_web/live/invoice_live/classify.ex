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
        case Invoices.get_invoice_with_details(company.id, id, role: role) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "Invoice not found.")
             |> redirect(to: ~p"/c/#{company.id}/invoices")}

          invoice ->
            can_set_category =
              invoice.type == :expense && Authorization.can?(role, :set_invoice_category)

            can_set_tags = Authorization.can?(role, :set_invoice_tags)
            can_manage_tags = Authorization.can?(role, :manage_tags)

            categories = Invoices.list_categories(company.id)
            grouped = group_categories(categories)
            all_tags = Invoices.list_tags(company.id, invoice.type)
            current_tag_ids = MapSet.new(invoice.tags, & &1.id)

            {:ok,
             socket
             |> assign(
               page_title: "Classify #{invoice.invoice_number}",
               invoice: invoice,
               categories: categories,
               grouped_categories: grouped,
               all_tags: all_tags,
               selected_category_id: invoice.category_id,
               selected_tag_ids: current_tag_ids,
               can_set_category: can_set_category,
               can_set_tags: can_set_tags,
               can_manage_tags: can_manage_tags,
               new_tag_form: to_form(%{"name" => ""}),
               tag_form_key: 0,
               confidence_threshold: InvoiceClassifier.confidence_threshold(),
               expanded_group: expanded_group_for(invoice.category_id, categories)
             )}
        end
    end
  end

  # --- Events ---

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("select_category", %{"id" => id}, socket) do
    if socket.assigns.can_set_category do
      category_id = if id == "", do: nil, else: id

      {:noreply,
       assign(socket,
         selected_category_id: category_id,
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

  def handle_event("toggle_tag", %{"tag-id" => tag_id}, socket) do
    if socket.assigns.can_set_tags do
      current = socket.assigns.selected_tag_ids

      updated =
        if MapSet.member?(current, tag_id),
          do: MapSet.delete(current, tag_id),
          else: MapSet.put(current, tag_id)

      {:noreply, assign(socket, :selected_tag_ids, updated)}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to manage tags.")}
    end
  end

  def handle_event("create_tag", %{"name" => name}, socket) do
    if socket.assigns.can_manage_tags do
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
        invoice = socket.assigns.invoice
        company_id = invoice.company_id

        case Invoices.create_tag(company_id, %{name: trimmed, type: invoice.type}) do
          {:ok, tag} ->
            {:noreply,
             socket
             |> assign(
               all_tags: Invoices.list_tags(company_id, invoice.type),
               selected_tag_ids: MapSet.put(socket.assigns.selected_tag_ids, tag.id),
               new_tag_form: to_form(%{"name" => ""}),
               tag_form_key: socket.assigns.tag_form_key + 1
             )}

          {:error, %Ecto.Changeset{} = cs} ->
            msg = changeset_message(cs)
            {:noreply, put_flash(socket, :error, "Failed to create tag: #{msg}")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to create tag.")}
        end
    end
  end

  @spec save_classification(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp save_classification(socket) do
    invoice = socket.assigns.invoice
    category_id = socket.assigns.selected_category_id
    tag_ids = MapSet.to_list(socket.assigns.selected_tag_ids)
    company = socket.assigns.current_company

    result =
      Invoices.with_manual_prediction(invoice, fn ->
        with {:ok, updated} <- Invoices.set_invoice_category(invoice, category_id),
             {:ok, _tags} <- Invoices.set_invoice_tags(updated.id, tag_ids) do
          {:ok, updated}
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
          confidence={@invoice.prediction_category_confidence}
          threshold={@confidence_threshold}
          label="category"
          testid="prediction-category-hint"
        />
      </section>

      <%!-- Tags Section --%>
      <section :if={@can_set_tags} class="mb-8" data-testid="tags-section">
        <h2 class="text-base font-semibold mb-3">Tags</h2>

        <div class="space-y-1">
          <label
            :for={tag <- @all_tags}
            class="flex items-center gap-2 cursor-pointer hover:bg-muted rounded px-2 py-1.5"
          >
            <input
              type="checkbox"
              class="size-3.5 rounded border border-input bg-background accent-shad-primary"
              checked={MapSet.member?(@selected_tag_ids, tag.id)}
              phx-click="toggle_tag"
              phx-value-tag-id={tag.id}
            />
            <span class="text-sm">{tag.name}</span>
          </label>
        </div>

        <.prediction_hint
          predicted_at={@invoice.prediction_predicted_at}
          status={@invoice.prediction_status}
          confidence={@invoice.prediction_tag_confidence}
          threshold={@confidence_threshold}
          label="tag"
          testid="prediction-tag-hint"
        />

        <%!-- New Tag Inline --%>
        <.form
          :if={@can_manage_tags}
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
    |> Enum.sort_by(fn {group, _} -> group end)
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

  @spec changeset_message(Ecto.Changeset.t()) :: String.t()
  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k} #{Enum.join(v, ", ")}" end)
  end
end
