defmodule KsefHubWeb.TagLive do
  @moduledoc """
  LiveView for managing invoice tags — create, edit, and delete.

  Tags are scoped to the current company and visible to all roles.
  Usage counts are shown from the many-to-many invoice_tags association.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Tag

  @doc "Initializes assigns and streams tags with usage counts for the current company."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  @impl true
  def mount(_params, _session, socket) do
    company_id = socket.assigns.current_company.id

    {:ok,
     socket
     |> assign(
       page_title: "Tags",
       company_id: company_id,
       editing: nil,
       form: new_changeset_form(company_id)
     )
     |> stream(:tags, Invoices.list_tags(company_id))}
  end

  # --- Events ---

  @doc "Handles validate, save, edit, cancel_edit, and delete events for tags."
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  @impl true
  def handle_event("validate", %{"tag" => params}, socket) do
    changeset = %{
      changeset_for(socket.assigns.editing, params, socket.assigns.company_id)
      | action: :validate
    }

    {:noreply, assign(socket, form: to_form(changeset, as: :tag))}
  end

  @impl true
  def handle_event("save", %{"tag" => params}, socket) do
    case socket.assigns.editing do
      nil -> create_tag(socket, params)
      tag -> update_tag(socket, tag, params)
    end
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, tag} <- Invoices.get_tag_with_usage_count(socket.assigns.company_id, uuid) do
      changeset = Tag.changeset(tag, %{})
      {:noreply, assign(socket, editing: tag, form: to_form(changeset, as: :tag))}
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid tag ID.")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Tag not found.")}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil, form: new_changeset_form(socket.assigns.company_id))}
  end

  @impl true
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

  @spec create_tag(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp create_tag(socket, params) do
    attrs = %{name: params["name"], description: params["description"]}

    case Invoices.create_tag(socket.assigns.company_id, attrs) do
      {:ok, tag} ->
        {:noreply,
         socket
         |> stream_insert(:tags, with_usage_count(tag, 0))
         |> assign(form: new_changeset_form(socket.assigns.company_id))
         |> put_flash(:info, "Tag created.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :tag))}
    end
  end

  @spec update_tag(Phoenix.LiveView.Socket.t(), Tag.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp update_tag(socket, tag, params) do
    attrs = %{name: params["name"], description: params["description"]}

    case Invoices.update_tag(tag, attrs) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> stream_insert(:tags, with_usage_count(updated, tag.usage_count))
         |> assign(editing: nil, form: new_changeset_form(socket.assigns.company_id))
         |> put_flash(:info, "Tag updated.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :tag))}
    end
  end

  @spec changeset_for(Tag.t() | nil, map(), Ecto.UUID.t()) :: Ecto.Changeset.t()
  defp changeset_for(nil, params, company_id), do: new_changeset(params, company_id)

  defp changeset_for(tag, params, _company_id),
    do: Tag.changeset(tag, %{name: params["name"], description: params["description"]})

  @spec new_changeset(map(), Ecto.UUID.t()) :: Ecto.Changeset.t()
  defp new_changeset(params, company_id) do
    %Tag{company_id: company_id}
    |> Tag.changeset(%{name: params["name"] || "", description: params["description"] || ""})
  end

  @spec new_changeset_form(Ecto.UUID.t()) :: Phoenix.HTML.Form.t()
  defp new_changeset_form(company_id), do: to_form(new_changeset(%{}, company_id), as: :tag)

  @spec with_usage_count(Tag.t(), non_neg_integer() | nil) :: Tag.t()
  defp with_usage_count(tag, count), do: %{tag | usage_count: count || 0}

  # --- Render ---

  @doc "Renders the tag management page with form and table."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Tags
      <:subtitle>Manage invoice tags for flexible multi-label annotation</:subtitle>
    </.header>

    <!-- Create / Edit Form -->
    <div class="rounded-xl border border-border bg-card text-card-foreground mt-6">
      <div class="p-6">
        <h2 class="text-base font-semibold">
          {if @editing, do: "Edit Tag", else: "New Tag"}
        </h2>
        <.form
          for={@form}
          phx-submit="save"
          phx-change="validate"
          class="flex flex-wrap gap-3 mt-3 items-end"
          id="tag-form"
        >
          <div class="flex-1 min-w-40">
            <label class="block text-xs text-muted-foreground mb-1">Name</label>
            <input
              type="text"
              name={@form[:name].name}
              value={@form[:name].value}
              placeholder="e.g. monthly"
              class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm shadow-sm"
              required
            />
            <.error :for={msg <- Enum.map(@form[:name].errors, &translate_error/1)}>
              {msg}
            </.error>
          </div>
          <div class="flex-1 min-w-40">
            <label class="block text-xs text-muted-foreground mb-1">Description</label>
            <input
              type="text"
              name={@form[:description].name}
              value={@form[:description].value}
              placeholder="Optional description"
              class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm shadow-sm"
            />
          </div>
          <div class="flex gap-2 items-end">
            <button
              type="submit"
              class="inline-flex items-center justify-center gap-2 h-9 px-3 text-sm font-medium rounded-md bg-shad-primary text-shad-primary-foreground hover:bg-shad-primary/90 shadow-xs transition-colors cursor-pointer"
            >
              {if @editing, do: "Update", else: "Create"}
            </button>
            <button
              :if={@editing}
              type="button"
              phx-click="cancel_edit"
              class="inline-flex items-center justify-center gap-2 h-9 px-3 text-sm font-medium rounded-md hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors cursor-pointer"
            >
              Cancel
            </button>
          </div>
        </.form>
      </div>
    </div>

    <!-- Tag Table -->
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
            <button
              phx-click="edit"
              phx-value-id={tag.id}
              class="inline-flex items-center justify-center gap-1 h-7 px-2 text-xs font-medium rounded-md hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors cursor-pointer"
            >
              Edit
            </button>
            <button
              phx-click="delete"
              phx-value-id={tag.id}
              data-confirm="Delete this tag? It will be removed from all invoices."
              class="inline-flex items-center justify-center gap-1 h-7 px-2 text-xs font-medium rounded-md hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors cursor-pointer text-shad-destructive"
            >
              Delete
            </button>
          </:action>
        </.table>
      </div>
    </div>
    """
  end
end
