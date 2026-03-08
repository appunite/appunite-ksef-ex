defmodule KsefHubWeb.InvoiceLive.PublicShow do
  @moduledoc """
  Public read-only LiveView for viewing invoices via shareable links.

  Validates the `token` query parameter against the invoice ID. If the current
  user has company membership, redirects to the authenticated detail page.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice

  import KsefHubWeb.InvoiceComponents

  # --- Mount ---

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  # --- Params ---

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(%{"id" => id} = params, _uri, socket) do
    token = params["token"]

    with {:token, token} when is_binary(token) <- {:token, token},
         {:invoice, %Invoice{} = invoice} <-
           {:invoice, Invoices.get_invoice_by_public_token(token)},
         {:match, true} <- {:match, invoice.id == id} do
      maybe_redirect_member(socket, invoice)
    else
      _ -> {:noreply, redirect(socket, to: ~p"/") |> put_flash(:error, "Invoice not found.")}
    end
  end

  @spec maybe_redirect_member(Phoenix.LiveView.Socket.t(), Invoice.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp maybe_redirect_member(socket, invoice) do
    user = socket.assigns[:current_user]

    if user && member_of_company?(user.id, invoice.company_id) do
      {:noreply, redirect(socket, to: ~p"/c/#{invoice.company_id}/invoices/#{invoice.id}")}
    else
      {:noreply,
       socket
       |> assign(
         page_title: "Invoice #{invoice.invoice_number}",
         invoice: invoice,
         html_preview: generate_preview(invoice)
       )}
    end
  end

  @spec member_of_company?(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  defp member_of_company?(user_id, company_id) do
    KsefHub.Companies.get_membership(user_id, company_id) != nil
  end

  # --- Render ---

  @doc "Renders the public read-only invoice view with details and preview."
  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Invoice {@invoice.invoice_number}
      <:subtitle>
        <.type_badge type={@invoice.type} />
      </:subtitle>
    </.header>

    <div class="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_minmax(0,2fr)] gap-6 mt-6">
      <!-- Invoice Metadata (read-only) -->
      <div class="space-y-4">
        <div class="card bg-base-100 border border-base-300">
          <div class="p-4">
            <h2 class="text-base font-semibold mb-2">Details</h2>
            <.invoice_details_table invoice={@invoice} />
          </div>
        </div>
      </div>
      <!-- Preview -->
      <div class="card bg-base-100 border border-base-300 h-full">
        <div class="p-4 flex flex-col h-full">
          <h2 class="text-base font-semibold mb-2">Preview</h2>
          <div
            :if={@html_preview}
            class="border border-base-300 rounded-lg overflow-hidden flex-1 min-h-[600px]"
          >
            <iframe
              srcdoc={@html_preview}
              class="w-full h-full bg-white"
              sandbox=""
              title="Invoice preview"
            >
            </iframe>
          </div>
          <div
            :if={!@html_preview && @invoice.pdf_file}
            class="border border-base-300 rounded-lg overflow-hidden flex-1 min-h-[600px]"
          >
            <iframe
              src={~p"/public/invoices/#{@invoice.id}/pdf?token=#{@invoice.public_token}&inline=1"}
              class="w-full h-full bg-white"
              title="Invoice PDF preview"
            >
            </iframe>
          </div>
          <p
            :if={!@html_preview && !@invoice.pdf_file}
            class="text-base-content/60 text-sm"
          >
            No preview available.
          </p>
        </div>
      </div>
    </div>
    """
  end
end
