defmodule KsefHubWeb.PaymentRequestLive.Form do
  @moduledoc """
  LiveView for creating or editing a payment request, optionally pre-filled from an invoice.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Authorization
  alias KsefHub.Invoices
  alias KsefHub.PaymentRequests
  alias KsefHub.PaymentRequests.PaymentRequest

  import KsefHubWeb.InvoiceComponents, only: [format_amount: 1, format_date: 1]

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    role = socket.assigns[:current_role]
    can_manage = Authorization.can?(role, :manage_payment_requests)

    {:ok, assign(socket, can_manage: can_manage)}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @spec apply_action(Phoenix.LiveView.Socket.t(), atom(), map()) :: Phoenix.LiveView.Socket.t()
  defp apply_action(socket, :new, params) do
    company = socket.assigns[:current_company]
    {invoice, attrs} = load_invoice_and_attrs(params, company)

    changeset = PaymentRequest.changeset(%PaymentRequest{}, attrs)

    socket
    |> assign(
      page_title: "New Payment Request",
      payment_request: %PaymentRequest{},
      invoice: invoice
    )
    |> assign(form: to_form(changeset, as: :payment_request))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    company = socket.assigns[:current_company]

    case PaymentRequests.get_payment_request(company.id, id) do
      nil ->
        socket
        |> put_flash(:error, "Payment request not found.")
        |> push_navigate(to: ~p"/c/#{company.id}/payment-requests")

      pr ->
        pr = KsefHub.Repo.preload(pr, [:invoice, :created_by, :updated_by])
        changeset = PaymentRequest.changeset(pr, %{})

        socket
        |> assign(
          page_title: "Edit Payment Request",
          payment_request: pr,
          invoice: pr.invoice
        )
        |> assign(form: to_form(changeset, as: :payment_request))
    end
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("validate", %{"payment_request" => params}, socket) do
    attrs = merge_address_fields(params)

    changeset =
      socket.assigns.payment_request
      |> PaymentRequest.changeset(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :payment_request))}
  end

  def handle_event("save", %{"payment_request" => params}, socket) do
    if socket.assigns.can_manage do
      do_save(socket, socket.assigns.live_action, params)
    else
      {:noreply,
       put_flash(socket, :error, "You do not have permission to manage payment requests.")}
    end
  end

  @spec do_save(Phoenix.LiveView.Socket.t(), atom(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_save(socket, :new, params) do
    company_id = socket.assigns.current_company.id
    user_id = socket.assigns.current_user.id
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

  defp do_save(socket, :edit, params) do
    company_id = socket.assigns.current_company.id
    attrs = merge_address_fields(params)

    user_id = socket.assigns.current_user.id

    case PaymentRequests.update_payment_request(socket.assigns.payment_request, user_id, attrs) do
      {:ok, _payment_request} ->
        {:noreply,
         socket
         |> put_flash(:info, "Payment request updated successfully.")
         |> push_navigate(to: ~p"/c/#{company_id}/payment-requests")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :payment_request))}
    end
  end

  @spec load_invoice_and_attrs(map(), map() | nil) :: {map() | nil, map()}
  defp load_invoice_and_attrs(%{"invoice_id" => invoice_id}, %{id: company_id})
       when is_binary(invoice_id) and invoice_id != "" do
    case Invoices.get_invoice(company_id, invoice_id) do
      nil ->
        {nil, %{}}

      invoice ->
        attrs = PaymentRequests.prefill_attrs_from_invoice(invoice)
        {invoice, attrs}
    end
  end

  defp load_invoice_and_attrs(_params, _company), do: {nil, %{}}

  @allowed_keys %{
    "recipient_name" => :recipient_name,
    "recipient_address" => :recipient_address,
    "amount" => :amount,
    "currency" => :currency,
    "title" => :title,
    "iban" => :iban,
    "note" => :note,
    "invoice_id" => :invoice_id
  }

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
    |> Map.put("recipient_address", address)
    |> Map.filter(fn {k, _v} -> Map.has_key?(@allowed_keys, k) end)
    |> Map.new(fn {k, v} -> {Map.fetch!(@allowed_keys, k), v} end)
  end

  @spec address_field(Phoenix.HTML.Form.t(), atom()) :: String.t()
  defp address_field(form, field) do
    case form[:recipient_address].value do
      %{^field => value} when is_binary(value) -> value
      _ -> ""
    end
  end

  @spec editing?(atom()) :: boolean()
  defp editing?(live_action), do: live_action == :edit

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {if editing?(@live_action), do: "Edit Payment Request", else: "New Payment Request"}
      <:subtitle>
        <span :if={@invoice}>
          {if editing?(@live_action), do: "Linked to", else: "Pre-filled from"} invoice {@invoice.invoice_number}
        </span>
        <span :if={!@invoice && !editing?(@live_action)}>
          Create a standalone payment request for {@current_company.name}
        </span>
      </:subtitle>
    </.header>

    <!-- Audit info (edit only) -->
    <div
      :if={editing?(@live_action)}
      class="mt-4 text-xs text-muted-foreground flex flex-wrap gap-x-4 gap-y-1"
    >
      <span>
        Created by {(@payment_request.created_by && @payment_request.created_by.name) || "unknown"} on {format_date(
          @payment_request.inserted_at
        )}
      </span>
      <span :if={@payment_request.updated_by}>
        &middot; Last edited by {@payment_request.updated_by.name} on {format_date(
          @payment_request.updated_at
        )}
      </span>
      <span :if={@payment_request.paid_at}>
        &middot; Paid on {format_date(@payment_request.paid_at)}
      </span>
    </div>

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

      <div class="space-y-1">
        <label for={@form[:note].id} class="block text-sm font-medium">
          Note <span class="text-muted-foreground font-normal">(optional)</span>
        </label>
        <textarea
          id={@form[:note].id}
          name={@form[:note].name}
          rows="3"
          class="w-full rounded-md border border-input bg-background px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          placeholder="Internal note..."
        >{@form[:note].value}</textarea>
      </div>

      <div class="flex items-center gap-3 pt-2">
        <.button type="submit" disabled={!@can_manage}>
          <.icon name="hero-check" class="size-4" />
          {if editing?(@live_action), do: "Save changes", else: "Create payment request"}
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
