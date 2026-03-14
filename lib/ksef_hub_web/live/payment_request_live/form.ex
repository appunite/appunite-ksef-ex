defmodule KsefHubWeb.PaymentRequestLive.Form do
  @moduledoc """
  LiveView for creating a new payment request, optionally pre-filled from an invoice.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Authorization
  alias KsefHub.Invoices
  alias KsefHub.PaymentRequests
  alias KsefHub.PaymentRequests.PaymentRequest

  import KsefHubWeb.InvoiceComponents, only: [format_amount: 1, format_date: 1]

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(params, _session, socket) do
    company = socket.assigns[:current_company]
    user = socket.assigns[:current_user]
    role = socket.assigns[:current_role]

    can_manage = Authorization.can?(role, :manage_payment_requests)

    {invoice, attrs} = load_invoice_and_attrs(params, company)

    changeset = PaymentRequest.changeset(%PaymentRequest{}, attrs)
    form = to_form(changeset, as: :payment_request)

    {:ok,
     assign(socket,
       page_title: "New Payment Request",
       form: form,
       invoice: invoice,
       can_manage: can_manage,
       company_id: company && company.id,
       user_id: user && user.id
     )}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("validate", %{"payment_request" => params}, socket) do
    attrs = merge_address_fields(params)

    changeset =
      %PaymentRequest{}
      |> PaymentRequest.changeset(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :payment_request))}
  end

  def handle_event("save", %{"payment_request" => params}, socket) do
    if socket.assigns.can_manage do
      do_save(socket, params)
    else
      {:noreply,
       put_flash(socket, :error, "You do not have permission to create payment requests.")}
    end
  end

  @spec do_save(Phoenix.LiveView.Socket.t(), map()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_save(socket, params) do
    company_id = socket.assigns.company_id
    user_id = socket.assigns.user_id
    attrs = merge_address_fields(params)

    case PaymentRequests.create_payment_request(company_id, user_id, attrs) do
      {:ok, _payment_request} ->
        {:noreply,
         socket
         |> put_flash(:info, "Payment request created successfully.")
         |> push_navigate(to: ~p"/c/#{company_id}/payment-requests")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :payment_request))}
    end
  end

  @spec load_invoice_and_attrs(map(), map() | nil) :: {map() | nil, map()}
  defp load_invoice_and_attrs(%{"invoice_id" => invoice_id}, %{id: company_id})
       when is_binary(invoice_id) and invoice_id != "" do
    case Invoices.get_invoice!(company_id, invoice_id) do
      nil ->
        {nil, %{}}

      invoice ->
        attrs = PaymentRequests.prefill_attrs_from_invoice(invoice)
        {invoice, attrs}
    end
  rescue
    Ecto.NoResultsError -> {nil, %{}}
  end

  defp load_invoice_and_attrs(_params, _company), do: {nil, %{}}

  @spec merge_address_fields(map()) :: map()
  defp merge_address_fields(params) do
    address =
      case params["recipient_address"] do
        addr when is_map(addr) ->
          %{
            street: addr["street"] || "",
            city: addr["city"] || "",
            postal_code: addr["postal_code"] || "",
            country: addr["country"] || ""
          }

        _ ->
          nil
      end

    params
    |> Map.delete("recipient_address")
    |> Map.put("recipient_address", address)
    |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
  rescue
    ArgumentError -> params
  end

  @spec address_field(Phoenix.HTML.Form.t(), atom()) :: String.t()
  defp address_field(form, field) do
    case form[:recipient_address].value do
      %{^field => value} when is_binary(value) -> value
      _ -> ""
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      New Payment Request
      <:subtitle>
        <span :if={@invoice}>
          Pre-filled from invoice {@invoice.invoice_number}
        </span>
        <span :if={!@invoice}>
          Create a standalone payment request for {@current_company.name}
        </span>
      </:subtitle>
    </.header>

    <!-- Linked invoice info -->
    <div
      :if={@invoice}
      class="mt-4 p-4 rounded-md border border-border bg-muted/50"
      data-testid="linked-invoice"
    >
      <h3 class="text-sm font-medium mb-2">Linked Invoice</h3>
      <table class="text-sm w-full">
        <tbody>
          <tr class="border-b border-border/50">
            <td class="py-1.5 pr-3 text-muted-foreground">Number</td>
            <td class="py-1.5 text-right">{@invoice.invoice_number}</td>
          </tr>
          <tr class="border-b border-border/50">
            <td class="py-1.5 pr-3 text-muted-foreground">Seller</td>
            <td class="py-1.5 text-right">{@invoice.seller_name}</td>
          </tr>
          <tr class="border-b border-border/50">
            <td class="py-1.5 pr-3 text-muted-foreground">Buyer</td>
            <td class="py-1.5 text-right">{@invoice.buyer_name}</td>
          </tr>
          <tr class="border-b border-border/50">
            <td class="py-1.5 pr-3 text-muted-foreground">Date</td>
            <td class="py-1.5 text-right">{format_date(@invoice.issue_date)}</td>
          </tr>
          <tr>
            <td class="py-1.5 pr-3 text-muted-foreground">Gross</td>
            <td class="py-1.5 text-right font-mono font-bold">
              {format_amount(@invoice.gross_amount)} {@invoice.currency}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Payment request form -->
    <.form
      for={@form}
      phx-change="validate"
      phx-submit="save"
      class="mt-6 space-y-6 max-w-xl"
    >
      <input :if={@invoice} type="hidden" name={@form[:invoice_id].name} value={@invoice.id} />

      <div class="space-y-1">
        <label for={@form[:recipient_name].id} class="block text-sm font-medium">
          Recipient name
        </label>
        <input
          type="text"
          id={@form[:recipient_name].id}
          name={@form[:recipient_name].name}
          value={@form[:recipient_name].value}
          class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          required
        />
        <.error :for={msg <- Enum.map(@form[:recipient_name].errors, &translate_error/1)}>
          {msg}
        </.error>
      </div>

      <fieldset class="space-y-3">
        <legend class="text-sm font-medium">Recipient address</legend>
        <div class="grid grid-cols-2 gap-3">
          <div class="col-span-2 space-y-1">
            <label class="block text-xs text-muted-foreground">Street</label>
            <input
              type="text"
              name="payment_request[recipient_address][street]"
              value={address_field(@form, :street)}
              class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            />
          </div>
          <div class="space-y-1">
            <label class="block text-xs text-muted-foreground">City</label>
            <input
              type="text"
              name="payment_request[recipient_address][city]"
              value={address_field(@form, :city)}
              class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            />
          </div>
          <div class="space-y-1">
            <label class="block text-xs text-muted-foreground">Postal code</label>
            <input
              type="text"
              name="payment_request[recipient_address][postal_code]"
              value={address_field(@form, :postal_code)}
              class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            />
          </div>
          <div class="col-span-2 space-y-1">
            <label class="block text-xs text-muted-foreground">Country</label>
            <input
              type="text"
              name="payment_request[recipient_address][country]"
              value={address_field(@form, :country)}
              class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            />
          </div>
        </div>
      </fieldset>

      <div class="grid grid-cols-2 gap-3">
        <div class="space-y-1">
          <label for={@form[:amount].id} class="block text-sm font-medium">Amount</label>
          <input
            type="number"
            step="0.01"
            min="0.01"
            id={@form[:amount].id}
            name={@form[:amount].name}
            value={@form[:amount].value}
            class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            required
          />
          <.error :for={msg <- Enum.map(@form[:amount].errors, &translate_error/1)}>
            {msg}
          </.error>
        </div>
        <div class="space-y-1">
          <label for={@form[:currency].id} class="block text-sm font-medium">Currency</label>
          <input
            type="text"
            id={@form[:currency].id}
            name={@form[:currency].name}
            value={@form[:currency].value || "PLN"}
            maxlength="3"
            class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            required
          />
          <.error :for={msg <- Enum.map(@form[:currency].errors, &translate_error/1)}>
            {msg}
          </.error>
        </div>
      </div>

      <div class="space-y-1">
        <label for={@form[:title].id} class="block text-sm font-medium">Title</label>
        <input
          type="text"
          id={@form[:title].id}
          name={@form[:title].name}
          value={@form[:title].value}
          class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          required
        />
        <.error :for={msg <- Enum.map(@form[:title].errors, &translate_error/1)}>
          {msg}
        </.error>
      </div>

      <div class="space-y-1">
        <label for={@form[:iban].id} class="block text-sm font-medium">IBAN</label>
        <input
          type="text"
          id={@form[:iban].id}
          name={@form[:iban].name}
          value={@form[:iban].value}
          class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm font-mono focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          required
        />
        <.error :for={msg <- Enum.map(@form[:iban].errors, &translate_error/1)}>
          {msg}
        </.error>
      </div>

      <div class="flex items-center gap-3 pt-2">
        <.button type="submit" disabled={!@can_manage}>
          <.icon name="hero-check" class="size-4" /> Create payment request
        </.button>
        <.button
          variant="outline"
          navigate={~p"/c/#{@current_company.id}/payment-requests"}
        >
          Cancel
        </.button>
      </div>
    </.form>
    """
  end
end
