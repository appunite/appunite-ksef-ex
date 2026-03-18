defmodule KsefHubWeb.CategoryLive.Form do
  @moduledoc """
  LiveView for creating or editing a single invoice category.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.EmojiGenerator
  alias KsefHub.Invoices
  alias KsefHub.Invoices.Category

  @doc "Initialises emoji_loading assign for the async emoji generator."
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok, assign(socket, emoji_loading: false)}
  end

  @doc "Routes to :new or :edit action based on live_action and URL params."
  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @spec apply_action(Phoenix.LiveView.Socket.t(), atom(), map()) :: Phoenix.LiveView.Socket.t()
  defp apply_action(socket, :new, _params) do
    company_id = socket.assigns.current_company.id
    changeset = Category.changeset(%Category{company_id: company_id}, %{})

    socket
    |> assign(
      page_title: "New Category",
      category: nil,
      company_id: company_id
    )
    |> assign(form: to_form(changeset, as: :category))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    company_id = socket.assigns.current_company.id

    case Invoices.get_category(company_id, id) do
      {:ok, category} ->
        changeset = Category.changeset(category, %{})

        socket
        |> assign(
          page_title: "Edit Category",
          category: category,
          company_id: company_id
        )
        |> assign(form: to_form(changeset, as: :category))

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Category not found.")
        |> push_navigate(to: ~p"/c/#{company_id}/categories")
    end
  end

  # --- Events ---

  @doc "Handles form validation, save, and emoji generation events."
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("validate", %{"category" => params}, socket) do
    changeset =
      %{changeset_for(socket, params) | action: :validate}

    {:noreply, assign(socket, form: to_form(changeset, as: :category))}
  end

  @impl true
  def handle_event("save", %{"category" => params}, socket) do
    case socket.assigns.category do
      nil -> create_category(socket, params)
      category -> update_category(socket, category, params)
    end
  end

  @impl true
  def handle_event("generate_emoji", _params, socket) do
    form = socket.assigns.form

    identifier = field_value(form, :identifier)

    if identifier == "" do
      {:noreply, put_flash(socket, :error, "Enter an identifier first.")}
    else
      socket = assign(socket, emoji_loading: true)

      context = %{
        identifier: identifier,
        name: field_value(form, :name),
        description: field_value(form, :description),
        examples: field_value(form, :examples)
      }

      Task.Supervisor.async_nolink(KsefHub.TaskSupervisor, fn ->
        EmojiGenerator.generate_emoji(context)
      end)

      {:noreply, socket}
    end
  end

  # --- Info handlers ---

  @doc "Receives async emoji generation results and task DOWN messages."
  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({ref, {:ok, emoji}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    params =
      current_form_params(socket)
      |> Map.put("emoji", emoji)

    changeset = changeset_for(socket, params)

    {:noreply,
     socket
     |> assign(
       emoji_loading: false,
       form: to_form(changeset, as: :category)
     )}
  end

  def handle_info({ref, {:error, _reason}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    {:noreply,
     socket
     |> assign(emoji_loading: false)
     |> put_flash(:error, "Failed to generate emoji.")}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, assign(socket, emoji_loading: false)}
  end

  # --- Private ---

  @spec create_category(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp create_category(socket, params) do
    company_id = socket.assigns.company_id

    case Invoices.create_category(company_id, atomize_params(params)) do
      {:ok, _category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category created.")
         |> push_navigate(to: ~p"/c/#{socket.assigns.current_company.id}/categories")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :category))}
    end
  end

  @spec update_category(Phoenix.LiveView.Socket.t(), Category.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp update_category(socket, category, params) do
    case Invoices.update_category(category, atomize_params(params)) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category updated.")
         |> push_navigate(to: ~p"/c/#{socket.assigns.current_company.id}/categories")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :category))}
    end
  end

  @spec changeset_for(Phoenix.LiveView.Socket.t(), map()) :: Ecto.Changeset.t()
  defp changeset_for(socket, params) do
    case socket.assigns.category do
      nil ->
        %Category{company_id: socket.assigns.company_id}
        |> Category.changeset(atomize_params(params))

      category ->
        Category.changeset(category, atomize_params(params))
    end
  end

  @spec field_value(Phoenix.HTML.Form.t(), atom()) :: String.t()
  defp field_value(form, field) do
    value = form[field].value
    if is_binary(value), do: String.trim(value), else: ""
  end

  @spec current_form_params(Phoenix.LiveView.Socket.t()) :: map()
  defp current_form_params(socket) do
    form = socket.assigns.form
    fields = ~w(identifier name emoji description examples sort_order)a

    Map.new(fields, fn field ->
      value = form[field].value
      {Atom.to_string(field), if(is_binary(value), do: value, else: to_string(value))}
    end)
  end

  @spec atomize_params(map()) :: map()
  defp atomize_params(params) do
    sort_order =
      case Integer.parse(params["sort_order"] || "0") do
        {n, ""} -> n
        _ -> 0
      end

    %{
      identifier: params["identifier"] || "",
      name: blank_to_nil(params["name"]),
      emoji: blank_to_nil(params["emoji"]),
      description: blank_to_nil(params["description"]),
      examples: blank_to_nil(params["examples"]),
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

  @doc "Renders the category create/edit form with emoji generation button."
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.header>
      {if @live_action == :edit, do: "Edit Category", else: "New Category"}
      <:subtitle>
        {if @live_action == :edit,
          do: "Update category details",
          else: "Create a new invoice classification category"}
      </:subtitle>
    </.header>

    <.form
      for={@form}
      phx-submit="save"
      phx-change="validate"
      class="mt-6 space-y-6 max-w-xl"
      id="category-form"
    >
      <div class="flex items-start gap-3">
        <div>
          <.input
            field={@form[:emoji]}
            label="Emoji"
            placeholder="📦"
            class="h-9 w-16 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring text-center"
          />
          <button
            type="button"
            phx-click="generate_emoji"
            disabled={@emoji_loading}
            class="mt-1 text-xs text-muted-foreground hover:text-foreground underline-offset-4 hover:underline disabled:opacity-50"
          >
            {if @emoji_loading, do: "Generating…", else: "Auto ✨"}
          </button>
        </div>
        <div class="flex-1">
          <.input
            field={@form[:identifier]}
            label="Identifier"
            placeholder="finance:invoices"
            required
          />
          <p class="mt-1 text-xs text-muted-foreground">
            Used by the ML classifier. Format: group:target
          </p>
        </div>
      </div>

      <.input
        field={@form[:name]}
        label="Display Name"
        placeholder="Invoices"
      />

      <.input
        field={@form[:description]}
        label="Description"
        placeholder="Optional description"
      />

      <.input
        field={@form[:examples]}
        label="Examples"
        placeholder="Example invoices for this category..."
      />

      <.input
        field={@form[:sort_order]}
        type="number"
        label="Sort Order"
        class="h-9 w-24 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
      />

      <div class="flex items-center gap-3 pt-2">
        <.button type="submit">
          {if @live_action == :edit, do: "Update Category", else: "Create Category"}
        </.button>
        <.button
          variant="outline"
          navigate={~p"/c/#{@current_company.id}/categories"}
        >
          Cancel
        </.button>
      </div>
    </.form>
    """
  end
end
