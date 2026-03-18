defmodule KsefHubWeb.TagLive.Form do
  @moduledoc """
  LiveView for creating or editing a single invoice tag.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Tag

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @spec apply_action(Phoenix.LiveView.Socket.t(), atom(), map()) :: Phoenix.LiveView.Socket.t()
  defp apply_action(socket, :new, _params) do
    company_id = socket.assigns.current_company.id
    changeset = Tag.changeset(%Tag{company_id: company_id}, %{})

    socket
    |> assign(
      page_title: "New Tag",
      tag: nil,
      company_id: company_id
    )
    |> assign(form: to_form(changeset, as: :tag))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    company_id = socket.assigns.current_company.id

    case Invoices.get_tag(company_id, id) do
      {:ok, tag} ->
        changeset = Tag.changeset(tag, %{})

        socket
        |> assign(
          page_title: "Edit Tag",
          tag: tag,
          company_id: company_id
        )
        |> assign(form: to_form(changeset, as: :tag))

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Tag not found.")
        |> push_navigate(to: ~p"/c/#{company_id}/tags")
    end
  end

  # --- Events ---

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("validate", %{"tag" => params}, socket) do
    changeset =
      %{changeset_for(socket, params) | action: :validate}

    {:noreply, assign(socket, form: to_form(changeset, as: :tag))}
  end

  @impl true
  def handle_event("save", %{"tag" => params}, socket) do
    case socket.assigns.tag do
      nil -> create_tag(socket, params)
      tag -> update_tag(socket, tag, params)
    end
  end

  # --- Private ---

  @spec create_tag(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp create_tag(socket, params) do
    attrs = %{name: params["name"], description: params["description"]}

    case Invoices.create_tag(socket.assigns.company_id, attrs) do
      {:ok, _tag} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tag created.")
         |> push_navigate(to: ~p"/c/#{socket.assigns.current_company.id}/tags")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :tag))}
    end
  end

  @spec update_tag(Phoenix.LiveView.Socket.t(), Tag.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp update_tag(socket, tag, params) do
    attrs = %{name: params["name"], description: params["description"]}

    case Invoices.update_tag(tag, attrs) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tag updated.")
         |> push_navigate(to: ~p"/c/#{socket.assigns.current_company.id}/tags")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :tag))}
    end
  end

  @spec changeset_for(Phoenix.LiveView.Socket.t(), map()) :: Ecto.Changeset.t()
  defp changeset_for(socket, params) do
    attrs = %{name: params["name"], description: params["description"]}

    case socket.assigns.tag do
      nil ->
        %Tag{company_id: socket.assigns.company_id}
        |> Tag.changeset(attrs)

      tag ->
        Tag.changeset(tag, attrs)
    end
  end

  @spec editing?(atom()) :: boolean()
  defp editing?(live_action), do: live_action == :edit

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.header>
      {if editing?(@live_action), do: "Edit Tag", else: "New Tag"}
      <:subtitle>
        {if editing?(@live_action),
          do: "Update tag details",
          else: "Create a new tag for invoice annotation"}
      </:subtitle>
    </.header>

    <.form
      for={@form}
      phx-submit="save"
      phx-change="validate"
      class="mt-6 space-y-6 max-w-xl"
      id="tag-form"
    >
      <.input field={@form[:name]} label="Name" placeholder="e.g. monthly" required />

      <.input field={@form[:description]} label="Description" placeholder="Optional description" />

      <div class="flex items-center gap-3 pt-2">
        <.button type="submit">
          {if editing?(@live_action), do: "Update Tag", else: "Create Tag"}
        </.button>
        <.button
          variant="outline"
          navigate={~p"/c/#{@current_company.id}/tags"}
        >
          Cancel
        </.button>
      </div>
    </.form>
    """
  end
end
