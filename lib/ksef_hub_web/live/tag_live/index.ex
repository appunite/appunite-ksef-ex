defmodule KsefHubWeb.TagLive.Index do
  @moduledoc """
  LiveView for listing and deleting invoice tags.

  Tags are scoped to the current company and visible to all roles.
  Supports Expense/Income tabs via `?type=` query param.
  Usage counts are shown from the many-to-many invoice_tags association.
  """
  use KsefHubWeb, :live_view

  import KsefHubWeb.SettingsComponents, only: [settings_layout: 1]

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Tag

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    company_id = socket.assigns.current_company.id

    {:ok, assign(socket, page_title: "Tags", company_id: company_id)}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _uri, socket) do
    type = parse_tag_type(params["type"])

    {:noreply,
     socket
     |> assign(active_type: type)
     |> stream(:tags, Invoices.list_tags(socket.assigns.company_id, type), reset: true)}
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

  # --- Private ---

  @spec parse_tag_type(String.t() | nil) :: :expense | :income
  defp parse_tag_type("income"), do: :income
  defp parse_tag_type(_), do: :expense

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.settings_layout
      current_path={@current_path}
      current_company={@current_company}
      current_role={@current_role}
    >
      <.header>
        Tags
        <:subtitle>Manage invoice tags for flexible multi-label annotation</:subtitle>
        <:actions>
          <.button navigate={~p"/c/#{@current_company.id}/settings/tags/new?type=#{@active_type}"}>
            New Tag
          </.button>
        </:actions>
      </.header>

      <%!-- Type Tabs --%>
      <div class="flex border-b border-border mt-4 mb-4">
        <.link
          patch={~p"/c/#{@current_company.id}/settings/tags?type=expense"}
          class={tab_class(@active_type == :expense)}
          aria-current={if @active_type == :expense, do: "page"}
        >
          Expense
        </.link>
        <.link
          patch={~p"/c/#{@current_company.id}/settings/tags?type=income"}
          class={tab_class(@active_type == :income)}
          aria-current={if @active_type == :income, do: "page"}
        >
          Income
        </.link>
      </div>

      <div class="rounded-lg border border-border overflow-hidden">
        <div class="overflow-x-auto">
          <.table
            id="tags"
            rows={@streams.tags}
            row_id={fn {id, _} -> id end}
            row_item={fn {_id, item} -> item end}
          >
            <:col :let={tag} label="Name" class="w-[30%]">
              <span data-testid={"tag-name-#{tag.id}"}>{tag.name}</span>
            </:col>
            <:col :let={tag} label="Description" class="w-[30%]">
              <span class="text-muted-foreground">{tag.description || "-"}</span>
            </:col>
            <:col :let={tag} label="Usage" class="text-center">
              <span class="font-mono">{tag.usage_count}</span>
            </:col>
            <:action :let={tag}>
              <.button
                variant="outline"
                size="sm"
                navigate={~p"/c/#{@current_company.id}/settings/tags/#{tag.id}/edit"}
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
    </.settings_layout>
    """
  end
end
