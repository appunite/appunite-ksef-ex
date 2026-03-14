defmodule KsefHubWeb.TagLive do
  @moduledoc """
  LiveView for managing invoice tags — create, edit, and delete.

  Tags are scoped to the current company and visible to all roles.
  Supports Expense/Income tabs via `?type=` query param.
  Usage counts are shown from the many-to-many invoice_tags association.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Tag

  @doc "Initializes assigns for the current company."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  @impl true
  def mount(_params, _session, socket) do
    company_id = socket.assigns.current_company.id

    {:ok,
     assign(socket,
       page_title: "Tags",
       company_id: company_id,
       editing: nil
     )}
  end

  @doc "Handles tab switching via query params."
  @impl true
  def handle_params(params, _uri, socket) do
    type = parse_tag_type(params["type"])
    company_id = socket.assigns.company_id

    {:noreply,
     socket
     |> assign(
       active_type: type,
       form: new_changeset_form(company_id, type)
     )
     |> stream(:tags, Invoices.list_tags(company_id, type), reset: true)}
  end

  # --- Events ---

  @doc "Handles validate, save, edit, cancel_edit, and delete events for tags."
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  @impl true
  def handle_event("validate", %{"tag" => params}, socket) do
    changeset = %{
      changeset_for(
        socket.assigns.editing,
        params,
        socket.assigns.company_id,
        socket.assigns.active_type
      )
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
    {:noreply,
     assign(socket,
       editing: nil,
       form: new_changeset_form(socket.assigns.company_id, socket.assigns.active_type)
     )}
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

  @spec parse_tag_type(String.t() | nil) :: :expense | :income
  defp parse_tag_type("income"), do: :income
  defp parse_tag_type(_), do: :expense

  @spec create_tag(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp create_tag(socket, params) do
    attrs = %{
      name: params["name"],
      description: params["description"],
      type: socket.assigns.active_type
    }

    case Invoices.create_tag(socket.assigns.company_id, attrs) do
      {:ok, tag} ->
        {:noreply,
         socket
         |> stream_insert(:tags, with_usage_count(tag, 0))
         |> assign(
           form: new_changeset_form(socket.assigns.company_id, socket.assigns.active_type)
         )
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
         |> assign(
           editing: nil,
           form: new_changeset_form(socket.assigns.company_id, socket.assigns.active_type)
         )
         |> put_flash(:info, "Tag updated.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :tag))}
    end
  end

  @spec changeset_for(Tag.t() | nil, map(), Ecto.UUID.t(), atom()) :: Ecto.Changeset.t()
  defp changeset_for(nil, params, company_id, type), do: new_changeset(params, company_id, type)

  defp changeset_for(tag, params, _company_id, _type),
    do: Tag.changeset(tag, %{name: params["name"], description: params["description"]})

  @spec new_changeset(map(), Ecto.UUID.t(), atom()) :: Ecto.Changeset.t()
  defp new_changeset(params, company_id, type) do
    %Tag{company_id: company_id, type: type}
    |> Tag.changeset(%{name: params["name"] || "", description: params["description"] || ""})
  end

  @spec new_changeset_form(Ecto.UUID.t(), atom()) :: Phoenix.HTML.Form.t()
  defp new_changeset_form(company_id, type),
    do: to_form(new_changeset(%{}, company_id, type), as: :tag)

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

    <!-- Type Tabs -->
    <div class="flex border-b border-border mb-4">
      <.link
        patch={~p"/c/#{@current_company.id}/tags?type=expense"}
        class={tab_class(@active_type == :expense)}
        aria-current={if @active_type == :expense, do: "page"}
      >
        Expense
      </.link>
      <.link
        patch={~p"/c/#{@current_company.id}/tags?type=income"}
        class={tab_class(@active_type == :income)}
        aria-current={if @active_type == :income, do: "page"}
      >
        Income
      </.link>
    </div>

    <!-- Create / Edit Form -->
    <.card class="mt-6">
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
          <.input field={@form[:name]} label="Name" placeholder="e.g. monthly" required />
        </div>
        <div class="flex-1 min-w-40">
          <.input field={@form[:description]} label="Description" placeholder="Optional description" />
        </div>
        <div class="flex gap-2 items-end">
          <.button type="submit">
            {if @editing, do: "Update", else: "Create"}
          </.button>
          <.button :if={@editing} variant="ghost" type="button" phx-click="cancel_edit">
            Cancel
          </.button>
        </div>
      </.form>
    </.card>

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
            <.button variant="outline" size="sm" phx-click="edit" phx-value-id={tag.id}>
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
