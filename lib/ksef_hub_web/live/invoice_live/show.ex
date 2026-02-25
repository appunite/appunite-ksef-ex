defmodule KsefHubWeb.InvoiceLive.Show do
  @moduledoc """
  LiveView for invoice detail page with HTML preview, metadata,
  category/tag editing, and approve/reject actions.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice

  import KsefHubWeb.InvoiceComponents

  # --- Mount ---

  @doc "Loads invoice by ID scoped to current company, generates HTML preview."
  @impl true
  def mount(%{"id" => id}, _session, socket) do
    company = socket.assigns.current_company

    cond do
      !socket.assigns[:current_user] ->
        {:ok,
         socket
         |> put_flash(:error, "You must be logged in to view invoices.")
         |> redirect(to: ~p"/")}

      !company ->
        {:ok,
         socket
         |> put_flash(:error, "No company selected.")
         |> redirect(to: ~p"/companies")}

      true ->
        mount_invoice(socket, company, id)
    end
  end

  @spec mount_invoice(Phoenix.LiveView.Socket.t(), map(), String.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  defp mount_invoice(socket, company, id) do
    role = socket.assigns[:current_role]

    case Invoices.get_invoice_with_details(company.id, id, role: role) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Invoice not found.")
         |> redirect(to: ~p"/invoices")}

      invoice ->
        {:ok,
         socket
         |> assign(
           page_title: "Invoice #{invoice.invoice_number}",
           invoice: invoice,
           html_preview: generate_preview(invoice),
           categories: Invoices.list_categories(company.id),
           all_tags: Invoices.list_tags(company.id),
           new_tag_name: ""
         )}
    end
  end

  # --- Events: Approve/Reject ---

  @doc "Handles approve and reject actions for expense invoices."
  @impl true
  def handle_event("approve", _params, socket) do
    case Invoices.approve_invoice(socket.assigns.invoice) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invoice approved.")
         |> assign(:invoice, updated)}

      {:error, {:invalid_type, _}} ->
        {:noreply, put_flash(socket, :error, "Only expense invoices can be approved.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to approve invoice.")}
    end
  end

  @impl true
  def handle_event("reject", _params, socket) do
    case Invoices.reject_invoice(socket.assigns.invoice) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invoice rejected.")
         |> assign(:invoice, updated)}

      {:error, {:invalid_type, _}} ->
        {:noreply, put_flash(socket, :error, "Only expense invoices can be rejected.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to reject invoice.")}
    end
  end

  # --- Events: Category ---

  @impl true
  def handle_event("set_category", %{"category_id" => ""}, socket) do
    with {:ok, updated} <- Invoices.set_invoice_category(socket.assigns.invoice, nil),
         {:ok, updated} <- Invoices.mark_prediction_manual(updated) do
      {:noreply, assign(socket, :invoice, reload_details(updated, socket))}
    else
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to update category.")}
    end
  end

  def handle_event("set_category", %{"category_id" => category_id}, socket) do
    with {:ok, updated} <- Invoices.set_invoice_category(socket.assigns.invoice, category_id),
         {:ok, updated} <- Invoices.mark_prediction_manual(updated) do
      {:noreply, assign(socket, :invoice, reload_details(updated, socket))}
    else
      {:error, :category_not_in_company} ->
        {:noreply, put_flash(socket, :error, "Category not found.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update category.")}
    end
  end

  # --- Events: Tags ---

  @impl true
  def handle_event("toggle_tag", %{"tag-id" => tag_id}, socket) do
    invoice = socket.assigns.invoice
    currently_assigned = tag_assigned?(invoice, tag_id)

    result =
      if currently_assigned,
        do: Invoices.remove_invoice_tag(invoice.id, tag_id),
        else: Invoices.add_invoice_tag(invoice.id, tag_id, invoice.company_id)

    case result do
      {:ok, _} ->
        {:noreply, assign(socket, :invoice, reload_details(invoice, socket))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update tags.")}
    end
  end

  @impl true
  def handle_event("new_tag_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, :new_tag_name, value)}
  end

  @impl true
  def handle_event("create_and_add_tag", %{"name" => name}, socket) do
    case String.trim(name) do
      "" -> {:noreply, socket}
      trimmed -> do_create_and_add_tag(socket, trimmed)
    end
  end

  @spec do_create_and_add_tag(Phoenix.LiveView.Socket.t(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_create_and_add_tag(socket, name) do
    company_id = socket.assigns.current_company.id
    invoice = socket.assigns.invoice

    with {:ok, tag} <- Invoices.create_tag(company_id, %{name: name}),
         {:ok, _} <- Invoices.add_invoice_tag(invoice.id, tag.id, company_id) do
      {:noreply,
       socket
       |> assign(
         invoice: reload_details(invoice, socket),
         all_tags: Invoices.list_tags(company_id),
         new_tag_name: ""
       )}
    else
      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, put_flash(socket, :error, "Failed to create tag: #{changeset_message(cs)}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create tag.")}
    end
  end

  @spec changeset_message(Ecto.Changeset.t()) :: String.t()
  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> Enum.map_join(", ", fn {k, v} -> "#{k} #{Enum.join(v, ", ")}" end)
  end

  # --- Private ---

  @spec reload_details(Invoice.t(), Phoenix.LiveView.Socket.t()) :: Invoice.t()
  defp reload_details(invoice, socket) do
    company_id = socket.assigns.current_company.id
    role = socket.assigns[:current_role]
    Invoices.get_invoice_with_details!(company_id, invoice.id, role: role)
  end

  @spec generate_preview(Invoice.t()) :: String.t() | nil
  defp generate_preview(invoice) do
    if invoice.xml_content do
      pdf_mod = Application.get_env(:ksef_hub, :pdf_generator, KsefHub.Pdf)

      metadata = %{ksef_number: invoice.ksef_number}

      case pdf_mod.generate_html(invoice.xml_content, metadata) do
        {:ok, html} -> html
        {:error, _} -> nil
      end
    end
  end

  @spec tag_assigned?(Invoice.t(), String.t()) :: boolean()
  defp tag_assigned?(invoice, tag_id) do
    Enum.any?(invoice.tags, &(&1.id == tag_id))
  end

  # --- Render ---

  @doc "Renders invoice detail page with metadata, preview, and action buttons."
  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Invoice {@invoice.invoice_number}
      <:subtitle>
        <.type_badge type={@invoice.type} />
        <.status_badge status={@invoice.status} />
        <.prediction_indicator prediction_status={@invoice.prediction_status} />
      </:subtitle>
      <:actions>
        <div class="flex gap-2">
          <div :if={@invoice.xml_content} class="dropdown dropdown-end">
            <div tabindex="0" role="button" class="btn btn-sm btn-outline">
              <.icon name="hero-arrow-down-tray" class="size-4" /> Download
              <.icon name="hero-chevron-down" class="size-3" />
            </div>
            <ul
              tabindex="0"
              class="dropdown-content z-50 menu p-2 border border-base-300 bg-base-100 rounded-box w-44"
            >
              <li><a href={~p"/invoices/#{@invoice.id}/pdf"}>PDF</a></li>
              <li><a href={~p"/invoices/#{@invoice.id}/xml"}>XML</a></li>
            </ul>
          </div>
          <button
            :if={@invoice.type == :expense && @invoice.status == :pending}
            phx-click="approve"
            class="btn btn-sm btn-success"
          >
            Approve
          </button>
          <button
            :if={@invoice.type == :expense && @invoice.status == :pending}
            phx-click="reject"
            class="btn btn-sm btn-error"
          >
            Reject
          </button>
        </div>
      </:actions>
    </.header>

    <div class="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_minmax(0,2fr)] gap-6 mt-6">
      <!-- Invoice Metadata -->
      <div class="space-y-4">
        <div class="card bg-base-100 border border-base-300">
          <div class="p-4">
            <h2 class="text-base font-semibold mb-2">Details</h2>
            <table class="text-sm w-full">
              <tbody>
                <tr class="border-b border-base-300/50">
                  <td class="py-1.5 pr-3 text-base-content/60 whitespace-nowrap">Number</td>
                  <td class="py-1.5 text-right">{@invoice.invoice_number}</td>
                </tr>
                <tr class="border-b border-base-300/50">
                  <td class="py-1.5 pr-3 text-base-content/60">Date</td>
                  <td class="py-1.5 text-right">{format_date(@invoice.issue_date)}</td>
                </tr>
                <tr class="border-b border-base-300/50">
                  <td class="py-1.5 pr-3 text-base-content/60">Seller</td>
                  <td class="py-1.5 text-right">
                    <div>{@invoice.seller_name}</div>
                    <div class="text-xs text-base-content/50">{@invoice.seller_nip}</div>
                  </td>
                </tr>
                <tr class="border-b border-base-300/50">
                  <td class="py-1.5 pr-3 text-base-content/60">Buyer</td>
                  <td class="py-1.5 text-right">
                    <div>{@invoice.buyer_name}</div>
                    <div class="text-xs text-base-content/50">{@invoice.buyer_nip}</div>
                  </td>
                </tr>
                <tr class="border-b border-base-300/50">
                  <td class="py-1.5 pr-3 text-base-content/60">Netto</td>
                  <td class="py-1.5 text-right font-mono">
                    {format_amount(@invoice.net_amount)} {@invoice.currency}
                  </td>
                </tr>
                <tr class="border-b border-base-300/50">
                  <td class="py-1.5 pr-3 text-base-content/60">VAT</td>
                  <td class="py-1.5 text-right font-mono">
                    {format_amount(@invoice.vat_amount)} {@invoice.currency}
                  </td>
                </tr>
                <tr class="border-b border-base-300/50">
                  <td class="py-1.5 pr-3 text-base-content/60">Brutto</td>
                  <td class="py-1.5 text-right font-mono font-bold">
                    {format_amount(@invoice.gross_amount)} {@invoice.currency}
                  </td>
                </tr>
                <tr :if={@invoice.ksef_number} class="border-b border-base-300/50">
                  <td class="py-1.5 pr-3 text-base-content/60">KSeF</td>
                  <td class="py-1.5 text-right font-mono text-xs break-all">
                    {@invoice.ksef_number}
                  </td>
                </tr>
                <tr :if={@invoice.ksef_acquisition_date}>
                  <td class="py-1.5 pr-3 text-base-content/60 whitespace-nowrap">Acquired</td>
                  <td class="py-1.5 text-right text-xs">
                    {format_datetime(@invoice.ksef_acquisition_date)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <!-- Category & Tags Card -->
        <div class="card bg-base-100 border border-base-300">
          <div class="p-4">
            <h2 class="text-base font-semibold mb-3">Classification</h2>
            <!-- Category Select -->
            <div class="mb-4">
              <label class="label"><span class="label-text text-xs">Category</span></label>
              <select
                phx-change="set_category"
                name="category_id"
                class="select select-sm select-bordered w-full"
                data-testid="category-select"
              >
                <option value="">No category</option>
                <option
                  :for={cat <- @categories}
                  value={cat.id}
                  selected={@invoice.category_id == cat.id}
                >
                  {if(cat.emoji, do: "#{cat.emoji} ", else: "")}{cat.name}
                </option>
              </select>
            </div>
            <!-- Tags -->
            <div>
              <label class="label"><span class="label-text text-xs">Tags</span></label>
              <div class="space-y-1">
                <label
                  :for={tag <- @all_tags}
                  class="flex items-center gap-2 cursor-pointer hover:bg-base-200 rounded px-2 py-1"
                >
                  <input
                    type="checkbox"
                    class="checkbox checkbox-xs"
                    checked={tag_assigned?(@invoice, tag.id)}
                    phx-click="toggle_tag"
                    phx-value-tag-id={tag.id}
                  />
                  <span class="text-sm">{tag.name}</span>
                </label>
              </div>
              <!-- New Tag Inline -->
              <form phx-submit="create_and_add_tag" class="flex gap-2 mt-2">
                <input
                  type="text"
                  name="name"
                  value={@new_tag_name}
                  phx-keyup="new_tag_input"
                  phx-debounce="300"
                  placeholder="New tag..."
                  class="input input-xs input-bordered flex-1"
                  data-testid="new-tag-input"
                />
                <button type="submit" class="btn btn-xs btn-primary">Add</button>
              </form>
            </div>
          </div>
        </div>
      </div>
      <!-- HTML Preview -->
      <div class="card bg-base-100 border border-base-300">
        <div class="p-4">
          <h2 class="text-base font-semibold mb-2">Preview</h2>
          <div :if={@html_preview} class="border border-base-300 rounded-lg overflow-hidden">
            <iframe
              srcdoc={@html_preview}
              class="w-full h-[600px] bg-white"
              sandbox=""
              title="Invoice preview"
            >
            </iframe>
          </div>
          <p :if={!@html_preview} class="text-base-content/60 text-sm">
            No preview available. XML content may be missing.
          </p>
        </div>
      </div>
    </div>

    <div class="mt-6">
      <.link navigate={~p"/invoices"} class="btn btn-ghost btn-sm">
        <.icon name="hero-arrow-left" class="size-4" /> Back to invoices
      </.link>
    </div>
    """
  end
end
