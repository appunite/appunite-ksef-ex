defmodule KsefHubWeb.CategoryLive do
  @moduledoc """
  LiveView for managing invoice categories — create, edit, and delete.

  Categories are scoped to the current company and visible to all roles.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Category

  @doc "Initializes assigns and streams categories for the current company."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  @impl true
  def mount(_params, _session, socket) do
    company_id = socket.assigns.current_company.id

    {:ok,
     socket
     |> assign(
       page_title: "Expense Categories",
       company_id: company_id,
       editing: nil,
       form: new_changeset_form(company_id)
     )
     |> stream(:categories, Invoices.list_categories(company_id))}
  end

  # --- Events ---

  @doc "Handles validate, save, edit, cancel_edit, and delete events for categories."
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  @impl true
  def handle_event("validate", %{"category" => params}, socket) do
    changeset = %{
      changeset_for(socket.assigns.editing, params, socket.assigns.company_id)
      | action: :validate
    }

    {:noreply, assign(socket, form: to_form(changeset, as: :category))}
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
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, category} <- Invoices.get_category(socket.assigns.company_id, uuid) do
      changeset = Category.changeset(category, %{})
      {:noreply, assign(socket, editing: category, form: to_form(changeset, as: :category))}
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid category ID.")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Category not found.")}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil, form: new_changeset_form(socket.assigns.company_id))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, category} <- Invoices.get_category(socket.assigns.company_id, uuid),
         {:ok, _} <- Invoices.delete_category(category) do
      {:noreply,
       socket
       |> stream_delete(:categories, category)
       |> put_flash(:info, "Category deleted.")}
    else
      :error ->
        {:noreply, put_flash(socket, :error, "Invalid category ID.")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> stream_delete(:categories, %Category{id: id})
         |> put_flash(:info, "Category not found or already deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete category.")}
    end
  end

  # --- Private ---

  @spec create_category(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp create_category(socket, params) do
    case Invoices.create_category(socket.assigns.company_id, atomize_params(params)) do
      {:ok, category} ->
        {:noreply,
         socket
         |> stream_insert(:categories, category)
         |> assign(form: new_changeset_form(socket.assigns.company_id))
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
         |> assign(editing: nil, form: new_changeset_form(socket.assigns.company_id))
         |> put_flash(:info, "Category updated.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :category))}
    end
  end

  @spec changeset_for(Category.t() | nil, map(), Ecto.UUID.t()) :: Ecto.Changeset.t()
  defp changeset_for(nil, params, company_id), do: new_changeset(params, company_id)

  defp changeset_for(category, params, _company_id),
    do: Category.changeset(category, atomize_params(params))

  @spec new_changeset(map(), Ecto.UUID.t()) :: Ecto.Changeset.t()
  defp new_changeset(params, company_id) do
    %Category{company_id: company_id}
    |> Category.changeset(atomize_params(params))
  end

  @spec new_changeset_form(Ecto.UUID.t()) :: Phoenix.HTML.Form.t()
  defp new_changeset_form(company_id), do: to_form(new_changeset(%{}, company_id), as: :category)

  @spec atomize_params(map()) :: map()
  defp atomize_params(params) do
    sort_order =
      case Integer.parse(params["sort_order"] || "0") do
        {n, ""} -> n
        _ -> 0
      end

    %{
      name: params["name"] || "",
      emoji: blank_to_nil(params["emoji"]),
      description: blank_to_nil(params["description"]),
      sort_order: sort_order
    }
  end

  @spec blank_to_nil(String.t() | nil) :: String.t() | nil
  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(str) do
    case String.trim(str) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  # --- Render ---

  @doc "Renders the category management page with form and table."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Expense Categories
      <:subtitle>Manage expense invoice classification categories</:subtitle>
    </.header>

    <!-- Create / Edit Form -->
    <.card class="mt-6">
      <h2 class="text-base font-semibold">
        {if @editing, do: "Edit Category", else: "New Category"}
      </h2>
      <.form
        for={@form}
        phx-submit="save"
        phx-change="validate"
        class="flex flex-wrap gap-3 mt-3 items-start"
        id="category-form"
      >
        <div>
          <.input
            field={@form[:emoji]}
            label="Emoji"
            placeholder="📦"
            class="h-9 w-16 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring text-center"
          />
        </div>
        <div class="flex-1 min-w-40">
          <.input
            field={@form[:name]}
            label="Name (group:target)"
            placeholder="finance:invoices"
            required
          />
        </div>
        <div class="flex-1 min-w-40">
          <.input
            field={@form[:description]}
            label="Description"
            placeholder="Optional description"
          />
        </div>
        <div>
          <.input
            field={@form[:sort_order]}
            type="number"
            label="Order"
            class="h-9 w-20 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          />
        </div>
        <div class="flex gap-2 items-end mt-4">
          <.button type="submit">
            {if @editing, do: "Update", else: "Create"}
          </.button>
          <.button :if={@editing} variant="ghost" type="button" phx-click="cancel_edit">
            Cancel
          </.button>
        </div>
      </.form>
    </.card>

    <!-- Category Table -->
    <div class="rounded-lg border border-border overflow-hidden mt-6">
      <div class="overflow-x-auto">
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
            <span class="text-muted-foreground">{cat.description || "-"}</span>
          </:col>
          <:col :let={cat} label="Order" class="w-20 text-center">
            {cat.sort_order}
          </:col>
          <:action :let={cat}>
            <.button variant="outline" size="sm" phx-click="edit" phx-value-id={cat.id}>
              Edit
            </.button>
            <.button
              variant="outline"
              size="sm"
              class="border-shad-destructive text-shad-destructive hover:bg-shad-destructive/10"
              phx-click="delete"
              phx-value-id={cat.id}
              data-confirm="Delete this category? Invoices with this category will become uncategorized."
            >
              Delete
            </.button>
          </:action>
        </.table>
      </div>
    </div>
    """
  end
end
