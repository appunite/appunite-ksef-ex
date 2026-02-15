defmodule KsefHubWeb.InvoiceLive.Show do
  @moduledoc """
  LiveView for invoice detail page with HTML preview, metadata, and approve/reject actions.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice

  import KsefHubWeb.InvoiceComponents

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
        role = socket.assigns[:current_role]

        case Invoices.get_invoice(company.id, id, role: role) do
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
  end

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

  @doc "Renders invoice detail page with metadata, preview, and action buttons."
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

    <div class="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_minmax(0,2fr)] gap-6 mt-6">
      <!-- Invoice Metadata -->
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
