defmodule KsefHubWeb.TagLive.Index do
  @moduledoc """
  LiveView for listing and deleting invoice tags.

  Tags are scoped to the current company and visible to all roles.
  Usage counts are shown from the many-to-many invoice_tags association.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Tag

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    company_id = socket.assigns.current_company.id

    {:ok,
     socket
     |> assign(page_title: "Tags", company_id: company_id)
     |> stream(:tags, Invoices.list_tags(company_id))}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("delete", %{"id" => id}, socket) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, tag} <- Invoices.get_tag(socket.assigns.company_id, uuid),
         {:ok, _} <- Invoices.delete_tag(tag) do
      {:noreply,
       socket
       |> stream_delete(:tags, tag)
       |> put_flash(:info, "Tag deleted.")}
    else
      :error ->
        {:noreply, put_flash(socket, :error, "Invalid tag ID.")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> stream_delete(:tags, %Tag{id: id})
         |> put_flash(:info, "Tag not found or already deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete tag.")}
    end
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.header>
      Tags
      <:subtitle>Manage invoice tags for flexible multi-label annotation</:subtitle>
      <:actions>
        <.button navigate={~p"/c/#{@current_company.id}/tags/new"}>
          New Tag
        </.button>
      </:actions>
    </.header>

    <div class="rounded-lg border border-border overflow-hidden mt-6">
      <div class="overflow-x-auto">
        <.table
          id="tags"
          rows={@streams.tags}
          row_id={fn {id, _} -> id end}
          row_item={fn {_id, item} -> item end}
        >
          <:col :let={tag} label="Name">
            <span data-testid={"tag-name-#{tag.id}"}>{tag.name}</span>
          </:col>
          <:col :let={tag} label="Description">
            <span class="text-muted-foreground">{tag.description || "-"}</span>
          </:col>
          <:col :let={tag} label="Usage" class="w-20 text-center">
            <span class="font-mono">{tag.usage_count}</span>
          </:col>
          <:action :let={tag}>
            <.button
              variant="outline"
              size="sm"
              navigate={~p"/c/#{@current_company.id}/tags/#{tag.id}/edit"}
            >
              Edit
            </.button>
            <.button
              variant="outline"
              size="sm"
              class="border-shad-destructive text-shad-destructive hover:bg-shad-destructive/10"
              phx-click="delete"
              phx-value-id={tag.id}
              data-confirm="Delete this tag? It will be removed from all invoices."
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
