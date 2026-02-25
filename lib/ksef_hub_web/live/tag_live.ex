defmodule KsefHubWeb.TagLive do
  @moduledoc """
  LiveView for managing invoice tags — create, edit, and delete.

  Tags are scoped to the current company and visible to all roles.
  Usage counts are shown from the many-to-many invoice_tags association.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Tag

  @impl true
  def mount(_params, _session, socket) do
    company_id = socket.assigns.current_company.id
    tags = Invoices.list_tags(company_id)

    {:ok,
     socket
     |> assign(
       page_title: "Tags",
       editing: nil,
       form: new_form()
     )
     |> stream(:tags, tags)}
  end

  # --- Events ---

  @impl true
  def handle_event("validate", %{"tag" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :tag))}
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
    company_id = socket.assigns.current_company.id

    case Invoices.get_tag(company_id, id) do
      {:ok, tag} ->
        form =
          %{"name" => tag.name, "description" => tag.description || ""}
          |> to_form(as: :tag)

        {:noreply, assign(socket, editing: tag, form: form)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Tag not found.")}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil, form: new_form())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    company_id = socket.assigns.current_company.id

    with {:ok, tag} <- Invoices.get_tag(company_id, id),
         {:ok, _} <- Invoices.delete_tag(tag) do
      {:noreply,
       socket
       |> stream_delete(:tags, tag)
       |> put_flash(:info, "Tag deleted.")}
    else
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to delete tag.")}
    end
  end

  # --- Private ---

  @spec create_tag(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp create_tag(socket, params) do
    company_id = socket.assigns.current_company.id

    case Invoices.create_tag(company_id, %{
           name: params["name"],
           description: params["description"]
         }) do
      {:ok, tag} ->
        {:noreply,
         socket
         |> stream_insert(:tags, tag)
         |> assign(form: new_form())
         |> put_flash(:info, "Tag created.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :tag))}
    end
  end

  @spec update_tag(Phoenix.LiveView.Socket.t(), Tag.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp update_tag(socket, tag, params) do
    case Invoices.update_tag(tag, %{name: params["name"], description: params["description"]}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> stream_insert(:tags, updated)
         |> assign(editing: nil, form: new_form())
         |> put_flash(:info, "Tag updated.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :tag))}
    end
  end

  @spec new_form() :: Phoenix.HTML.Form.t()
  defp new_form do
    to_form(%{"name" => "", "description" => ""}, as: :tag)
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Tags
      <:subtitle>Manage invoice tags for flexible multi-label annotation</:subtitle>
    </.header>

    <!-- Create / Edit Form -->
    <div class="card bg-base-100 border border-base-300 mt-6">
      <div class="p-5">
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
            <label class="block text-xs text-base-content/60 mb-1">Name</label>
            <input
              type="text"
              name={@form[:name].name}
              value={@form[:name].value}
              placeholder="e.g. monthly"
              class="input input-sm input-bordered w-full"
              required
            />
            <.error :for={msg <- Enum.map(@form[:name].errors, &translate_error/1)}>
              {msg}
            </.error>
          </div>
          <div class="flex-1 min-w-40">
            <label class="block text-xs text-base-content/60 mb-1">Description</label>
            <input
              type="text"
              name={@form[:description].name}
              value={@form[:description].value}
              placeholder="Optional description"
              class="input input-sm input-bordered w-full"
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

    <!-- Tag Table -->
    <div class="mt-6 overflow-x-auto">
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
          <span class="text-base-content/60">{tag.description || "-"}</span>
        </:col>
        <:col :let={tag} label="Usage" class="w-20 text-center">
          <span class="font-mono">{tag.usage_count}</span>
        </:col>
        <:action :let={tag}>
          <button phx-click="edit" phx-value-id={tag.id} class="btn btn-ghost btn-xs">
            Edit
          </button>
          <button
            phx-click="delete"
            phx-value-id={tag.id}
            data-confirm="Delete this tag? It will be removed from all invoices."
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
