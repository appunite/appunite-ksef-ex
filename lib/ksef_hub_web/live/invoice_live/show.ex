defmodule KsefHubWeb.InvoiceLive.Show do
  @moduledoc """
  LiveView for invoice detail page with HTML preview, metadata, and approve/reject actions.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Invoices

  import KsefHubWeb.InvoiceComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Invoices.get_invoice(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Invoice not found.")
         |> redirect(to: ~p"/invoices")}

      invoice ->
        html_preview = generate_preview(invoice)

        {:ok,
         assign(socket,
           page_title: "Invoice #{invoice.invoice_number}",
           invoice: invoice,
           html_preview: html_preview
         )}
    end
  end

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

  defp generate_preview(invoice) do
    if invoice.xml_content do
      pdf_mod = Application.get_env(:ksef_hub, :pdf_generator, KsefHub.Pdf)

      case pdf_mod.generate_html(invoice.xml_content) do
        {:ok, html} -> html
        {:error, _} -> nil
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Invoice {@invoice.invoice_number}
      <:subtitle>
        <.type_badge type={@invoice.type} />
        <.status_badge status={@invoice.status} />
      </:subtitle>
      <:actions>
        <div class="flex gap-2">
          <.link
            :if={@invoice.xml_content}
            href={~p"/invoices/#{@invoice.id}/pdf"}
            class="btn btn-sm btn-outline"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> PDF
          </.link>
          <button
            :if={@invoice.type == "expense" && @invoice.status == "pending"}
            phx-click="approve"
            class="btn btn-sm btn-success"
          >
            Approve
          </button>
          <button
            :if={@invoice.type == "expense" && @invoice.status == "pending"}
            phx-click="reject"
            class="btn btn-sm btn-error"
          >
            Reject
          </button>
        </div>
      </:actions>
    </.header>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
      <!-- Invoice Metadata -->
      <div class="card bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title text-base mb-2">Details</h2>
          <.list>
            <:item title="Invoice Number">{@invoice.invoice_number}</:item>
            <:item title="Type"><.type_badge type={@invoice.type} /></:item>
            <:item title="Status"><.status_badge status={@invoice.status} /></:item>
            <:item title="Issue Date">{format_date(@invoice.issue_date)}</:item>
            <:item title="Seller">
              <span class="font-medium">{@invoice.seller_name}</span>
              <span class="text-sm text-base-content/60 ml-1">NIP: {@invoice.seller_nip}</span>
            </:item>
            <:item title="Buyer">
              <span class="font-medium">{@invoice.buyer_name}</span>
              <span class="text-sm text-base-content/60 ml-1">NIP: {@invoice.buyer_nip}</span>
            </:item>
            <:item title="Net Amount">
              <span class="font-mono">{format_amount(@invoice.net_amount)}</span>
              {@invoice.currency}
            </:item>
            <:item title="VAT Amount">
              <span class="font-mono">{format_amount(@invoice.vat_amount)}</span>
              {@invoice.currency}
            </:item>
            <:item title="Gross Amount">
              <span class="font-mono font-bold">{format_amount(@invoice.gross_amount)}</span>
              {@invoice.currency}
            </:item>
            <:item :if={@invoice.ksef_number} title="KSeF Number">
              <span class="font-mono text-sm">{@invoice.ksef_number}</span>
            </:item>
            <:item :if={@invoice.ksef_acquisition_date} title="KSeF Acquisition">
              {format_datetime(@invoice.ksef_acquisition_date)}
            </:item>
          </.list>
        </div>
      </div>
      
    <!-- HTML Preview -->
      <div class="card bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title text-base mb-2">Preview</h2>
          <div :if={@html_preview} class="border border-base-300 rounded-lg overflow-hidden">
            <iframe
              srcdoc={@html_preview}
              class="w-full h-96 bg-white"
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
