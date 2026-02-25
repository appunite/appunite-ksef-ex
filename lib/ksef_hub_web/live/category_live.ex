defmodule KsefHubWeb.CategoryLive do
  @moduledoc """
  LiveView for managing invoice categories — create, edit, and delete.

  Categories are scoped to the current company and visible to all roles.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Category

  @impl true
  def mount(_params, _session, socket) do
    company_id = socket.assigns.current_company.id
    categories = Invoices.list_categories(company_id)

    {:ok,
     socket
     |> assign(
       page_title: "Categories",
       editing: nil,
       form: new_form()
     )
     |> stream(:categories, categories)}
  end

  # --- Events ---

  @impl true
  def handle_event("validate", %{"category" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :category))}
  end

  @impl true
  def handle_event("save", %{"category" => params}, socket) do
    case socket.assigns.editing do
      nil -> create_category(socket, params)
      category -> update_category(socket, category, params)
    end
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    company_id = socket.assigns.current_company.id

    case Invoices.get_category(company_id, id) do
      {:ok, category} ->
        form =
          %{
            "name" => category.name,
            "emoji" => category.emoji || "",
            "description" => category.description || "",
            "sort_order" => to_string(category.sort_order)
          }
          |> to_form(as: :category)

        {:noreply, assign(socket, editing: category, form: form)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Category not found.")}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil, form: new_form())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    company_id = socket.assigns.current_company.id

    with {:ok, category} <- Invoices.get_category(company_id, id),
         {:ok, _} <- Invoices.delete_category(category) do
      {:noreply,
       socket
       |> stream_delete(:categories, category)
       |> put_flash(:info, "Category deleted.")}
    else
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to delete category.")}
    end
  end

  # --- Private ---

  @spec create_category(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp create_category(socket, params) do
    company_id = socket.assigns.current_company.id

    case Invoices.create_category(company_id, atomize_params(params)) do
      {:ok, category} ->
        {:noreply,
         socket
         |> stream_insert(:categories, category)
         |> assign(form: new_form())
         |> put_flash(:info, "Category created.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :category))}
    end
  end

  @spec update_category(Phoenix.LiveView.Socket.t(), Category.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp update_category(socket, category, params) do
    case Invoices.update_category(category, atomize_params(params)) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> stream_insert(:categories, updated)
         |> assign(editing: nil, form: new_form())
         |> put_flash(:info, "Category updated.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :category))}
    end
  end

  @spec new_form() :: Phoenix.HTML.Form.t()
  defp new_form do
    to_form(%{"name" => "", "emoji" => "", "description" => "", "sort_order" => "0"},
      as: :category
    )
  end

  @spec atomize_params(map()) :: map()
  defp atomize_params(params) do
    sort_order =
      case Integer.parse(params["sort_order"] || "0") do
        {n, _} -> n
        :error -> 0
      end

    %{
      name: params["name"],
      emoji: params["emoji"],
      description: params["description"],
      sort_order: sort_order
    }
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Categories
      <:subtitle>Manage invoice classification categories</:subtitle>
    </.header>

    <!-- Create / Edit Form -->
    <div class="card bg-base-100 border border-base-300 mt-6">
      <div class="p-5">
        <h2 class="text-base font-semibold">
          {if @editing, do: "Edit Category", else: "New Category"}
        </h2>
        <.form
          for={@form}
          phx-submit="save"
          phx-change="validate"
          class="grid grid-cols-1 sm:grid-cols-[auto_1fr_2fr_auto_auto] gap-3 mt-3 items-end"
          id="category-form"
        >
          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Emoji</span></label>
            <input
              type="text"
              name={@form[:emoji].name}
              value={@form[:emoji].value}
              placeholder="📦"
              class="input input-sm input-bordered w-16 text-center"
            />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Name (group:target)</span></label>
            <input
              type="text"
              name={@form[:name].name}
              value={@form[:name].value}
              placeholder="finance:invoices"
              class="input input-sm input-bordered"
              required
            />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Description</span></label>
            <input
              type="text"
              name={@form[:description].name}
              value={@form[:description].value}
              placeholder="Optional description"
              class="input input-sm input-bordered"
            />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Order</span></label>
            <input
              type="number"
              name={@form[:sort_order].name}
              value={@form[:sort_order].value}
              class="input input-sm input-bordered w-20"
            />
          </div>
          <div class="flex gap-2 items-end">
            <button type="submit" class="btn btn-primary btn-sm">
              {if @editing, do: "Update", else: "Create"}
            </button>
            <button
              :if={@editing}
              type="button"
              phx-click="cancel_edit"
              class="btn btn-ghost btn-sm"
            >
              Cancel
            </button>
          </div>
        </.form>
      </div>
    </div>

    <!-- Category Table -->
    <div class="mt-6 overflow-x-auto">
      <.table
        id="categories"
        rows={@streams.categories}
        row_id={fn {id, _} -> id end}
        row_item={fn {_id, item} -> item end}
      >
        <:col :let={cat} label="Emoji" class="w-16 text-center">
          {cat.emoji || "-"}
        </:col>
        <:col :let={cat} label="Name">
          <span data-testid={"category-name-#{cat.id}"}>{cat.name}</span>
        </:col>
        <:col :let={cat} label="Description">
          <span class="text-base-content/60">{cat.description || "-"}</span>
        </:col>
        <:col :let={cat} label="Order" class="w-20 text-center">
          {cat.sort_order}
        </:col>
        <:action :let={cat}>
          <button phx-click="edit" phx-value-id={cat.id} class="btn btn-ghost btn-xs">
            Edit
          </button>
          <button
            phx-click="delete"
            phx-value-id={cat.id}
            data-confirm="Delete this category? Invoices with this category will become uncategorized."
            class="btn btn-ghost btn-xs text-error"
          >
            Delete
          </button>
        </:action>
      </.table>
    </div>
    """
  end
end
