defmodule KsefHubWeb.CategoryLive.Index do
  @moduledoc """
  LiveView for listing and deleting invoice categories.

  Categories are scoped to the current company and visible to all roles.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Category

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    company_id = socket.assigns.current_company.id

    {:ok,
     socket
     |> assign(page_title: "Categories", company_id: company_id)
     |> stream(:categories, Invoices.list_categories(company_id))}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
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

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.header>
      Categories
      <:subtitle>Manage invoice classification categories</:subtitle>
      <:actions>
        <.button navigate={~p"/c/#{@current_company.id}/categories/new"}>
          New Category
        </.button>
      </:actions>
    </.header>

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
          <:col :let={cat} label="Identifier">
            <span data-testid={"category-identifier-#{cat.id}"}>{cat.identifier}</span>
          </:col>
          <:col :let={cat} label="Name">
            <span data-testid={"category-name-#{cat.id}"}>{cat.name || "-"}</span>
          </:col>
          <:col :let={cat} label="Description">
            <span class="text-muted-foreground">{cat.description || "-"}</span>
          </:col>
          <:col :let={cat} label="Order" class="w-20 text-center">
            {cat.sort_order}
          </:col>
          <:action :let={cat}>
            <.button
              variant="outline"
              size="sm"
              navigate={~p"/c/#{@current_company.id}/categories/#{cat.id}/edit"}
            >
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
