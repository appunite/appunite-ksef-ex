defmodule KsefHubWeb.InvoiceLive.Show do
  @moduledoc """
  LiveView for invoice detail page with HTML preview, metadata,
  category/tag editing, edit form, and approve/reject actions.
  """
  use KsefHubWeb, :live_view

  require Logger

  alias KsefHub.Authorization
  alias KsefHub.InvoiceClassifier
  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice
  alias KsefHub.PaymentRequests

  import KsefHubWeb.InvoiceComponents

  # --- Mount ---

  @doc "Loads invoice by ID scoped to current company, generates HTML preview."
  @impl true
  def mount(%{"id" => id}, _session, socket) do
    company = socket.assigns[:current_company]

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
         |> redirect(to: ~p"/c/#{company.id}/invoices")}

      invoice ->
        data_editable = Invoice.data_editable?(invoice)
        auto_edit = data_editable and invoice.extraction_status in [:partial, :failed]
        can_mutate = Authorization.can?(role, :update_invoice)
        can_approve = Authorization.can?(role, :approve_invoice)
        can_set_category = Authorization.can?(role, :set_invoice_category)
        can_set_tags = Authorization.can?(role, :set_invoice_tags)
        can_manage_tags = Authorization.can?(role, :manage_tags)
        can_manage_payment_requests = Authorization.can?(role, :manage_payment_requests)
        can_view_payment_requests = Authorization.can?(role, :view_payment_requests)
        payment_status = PaymentRequests.payment_status_for_invoice(invoice.id)
        invoice_payment_requests = PaymentRequests.list_for_invoice(invoice.id)

        {:ok,
         socket
         |> assign(
           page_title: "Invoice #{invoice.invoice_number}",
           invoice: invoice,
           data_editable: data_editable,
           can_mutate: can_mutate,
           can_approve: can_approve,
           can_set_category: can_set_category,
           can_set_tags: can_set_tags,
           can_manage_tags: can_manage_tags,
           can_manage_payment_requests: can_manage_payment_requests,
           can_view_payment_requests: can_view_payment_requests,
           payment_status: payment_status,
           invoice_payment_requests: invoice_payment_requests,
           html_preview: generate_preview(invoice),
           categories: Invoices.list_categories(company.id),
           editing: auto_edit && can_mutate,
           edit_form: build_edit_form(invoice),
           billing_date_form: billing_date_form(invoice),
           editing_note: false,
           note_form: note_form(invoice),
           comments: Invoices.list_invoice_comments(company.id, invoice.id),
           comment_form: comment_form(),
           extracting: false,
           extract_ref: nil,
           comment_form_key: 0,
           editing_comment_id: nil,
           edit_comment_form: nil,
           confidence_threshold: InvoiceClassifier.confidence_threshold()
         )}
    end
  end

  # --- Authorization guard ---
  # Catch-all for mutation events when the user lacks permission.

  @mutation_events ~w(re_extract dismiss_duplicate confirm_duplicate
    toggle_edit save_edit edit_note save_note save_billing_date copy_public_link)

  @approve_events ~w(approve reject)

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event(event, _params, %{assigns: %{can_mutate: false}} = socket)
      when event in @mutation_events do
    {:noreply, put_flash(socket, :error, "You don't have permission to modify this invoice.")}
  end

  def handle_event(event, _params, %{assigns: %{can_approve: false}} = socket)
      when event in @approve_events do
    {:noreply,
     put_flash(socket, :error, "You don't have permission to approve or reject invoices.")}
  end

  # --- Events: Re-extract ---

  def handle_event("re_extract", _params, socket) do
    invoice = socket.assigns.invoice

    if invoice.source in [:pdf_upload, :email] and not socket.assigns.extracting do
      company = socket.assigns.current_company

      task =
        Task.Supervisor.async_nolink(KsefHub.TaskSupervisor, fn ->
          Invoices.re_extract_invoice(invoice, company)
        end)

      {:noreply, assign(socket, extracting: true, extract_ref: task.ref)}
    else
      {:noreply, socket}
    end
  end

  # --- Events: Approve/Reject ---
  def handle_event(
        "approve",
        _params,
        %{assigns: %{invoice: %{duplicate_status: :confirmed}}} = socket
      ) do
    {:noreply, put_flash(socket, :error, "Cannot approve a confirmed duplicate.")}
  end

  def handle_event("approve", _params, socket) do
    case Invoices.approve_invoice(socket.assigns.invoice) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invoice approved.")
         |> assign(:invoice, reload_details(updated, socket))}

      {:error, {:invalid_type, _}} ->
        {:noreply, put_flash(socket, :error, "Only expense invoices can be approved.")}

      {:error, :incomplete_extraction} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Cannot approve: extraction is incomplete. Please review and complete all missing fields before approving."
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to approve invoice.")}
    end
  end

  @impl true
  def handle_event(
        "reject",
        _params,
        %{assigns: %{invoice: %{duplicate_status: :confirmed}}} = socket
      ) do
    {:noreply, put_flash(socket, :error, "Cannot reject a confirmed duplicate.")}
  end

  def handle_event("reject", _params, socket) do
    case Invoices.reject_invoice(socket.assigns.invoice) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invoice rejected.")
         |> assign(:invoice, reload_details(updated, socket))}

      {:error, {:invalid_type, _}} ->
        {:noreply, put_flash(socket, :error, "Only expense invoices can be rejected.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to reject invoice.")}
    end
  end

  # --- Events: Duplicate ---

  @impl true
  def handle_event("dismiss_duplicate", _params, socket) do
    invoice = socket.assigns.invoice

    if invoice.duplicate_of_id && invoice.duplicate_status == :suspected do
      case Invoices.dismiss_duplicate(invoice) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> put_flash(:info, "Duplicate dismissed.")
           |> assign(:invoice, reload_details(updated, socket))}

        {:error, :not_a_duplicate} ->
          {:noreply, put_flash(socket, :error, "This invoice is not marked as a duplicate.")}

        {:error, :invalid_status} ->
          {:noreply, put_flash(socket, :error, "Cannot dismiss duplicate in its current status.")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to dismiss duplicate.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Stale or invalid duplicate state.")}
    end
  end

  @impl true
  def handle_event("confirm_duplicate", _params, socket) do
    invoice = socket.assigns.invoice

    if invoice.duplicate_of_id && invoice.duplicate_status == :suspected do
      case Invoices.confirm_duplicate(invoice) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> put_flash(:info, "Duplicate confirmed.")
           |> assign(:invoice, reload_details(updated, socket))}

        {:error, :not_a_duplicate} ->
          {:noreply, put_flash(socket, :error, "This invoice is not marked as a duplicate.")}

        {:error, :invalid_status} ->
          {:noreply, put_flash(socket, :error, "Cannot confirm duplicate in its current status.")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to confirm duplicate.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Stale or invalid duplicate state.")}
    end
  end

  # --- Events: Edit ---

  @impl true
  def handle_event("toggle_edit", _params, %{assigns: %{data_editable: false}} = socket) do
    {:noreply, put_flash(socket, :error, "KSeF invoice data cannot be edited.")}
  end

  def handle_event("toggle_edit", _params, socket) do
    {:noreply,
     assign(socket,
       editing: true,
       edit_form: build_edit_form(socket.assigns.invoice)
     )}
  end

  @impl true
  def handle_event("validate_edit", %{"invoice" => params}, socket) do
    params = normalize_billing_date_param(params)

    changeset =
      socket.assigns.invoice
      |> Invoice.edit_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, edit_form: to_form(changeset, as: :invoice))}
  end

  @impl true
  def handle_event("save_edit", %{"invoice" => params}, socket) do
    params = normalize_billing_date_param(params)

    case Invoices.update_invoice_fields(socket.assigns.invoice, params) do
      {:ok, updated} ->
        reloaded = reload_details(updated, socket)

        {:noreply,
         socket
         |> put_flash(:info, "Invoice updated.")
         |> assign(
           invoice: reloaded,
           editing: false,
           edit_form: build_edit_form(reloaded),
           billing_date_form: billing_date_form(reloaded)
         )}

      {:error, :ksef_not_editable} ->
        reloaded = reload_details(socket.assigns.invoice, socket)

        {:noreply,
         socket
         |> put_flash(:error, "KSeF invoice data cannot be edited.")
         |> assign(
           invoice: reloaded,
           data_editable: Invoice.data_editable?(reloaded),
           editing: false
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, edit_form: to_form(changeset, as: :invoice))}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     assign(socket,
       editing: false,
       edit_form: build_edit_form(socket.assigns.invoice)
     )}
  end

  # --- Events: Share ---

  @impl true
  def handle_event("copy_public_link", _params, socket) do
    invoice = socket.assigns.invoice

    {:ok, updated} = Invoices.ensure_public_token(invoice)
    url = url(~p"/public/invoices/#{updated.id}?token=#{updated.public_token}")

    {:noreply,
     socket
     |> assign(:invoice, %{invoice | public_token: updated.public_token})
     |> push_event("copy_to_clipboard", %{text: url})
     |> put_flash(:info, "Public link copied to clipboard.")}
  end

  # --- Events: Note ---

  @impl true
  def handle_event("edit_note", _params, socket) do
    {:noreply, assign(socket, editing_note: true, note_form: note_form(socket.assigns.invoice))}
  end

  @impl true
  def handle_event("save_note", %{"note" => note}, socket) do
    case Invoices.update_invoice_note(socket.assigns.invoice, %{note: note}) do
      {:ok, updated} ->
        reloaded = reload_details(updated, socket)

        {:noreply,
         socket
         |> assign(invoice: reloaded, editing_note: false, note_form: note_form(reloaded))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to save note.")
         |> assign(
           note_form: to_form(%{"note" => Ecto.Changeset.get_field(changeset, :note) || ""})
         )}
    end
  end

  @impl true
  def handle_event("cancel_note", _params, socket) do
    {:noreply, assign(socket, editing_note: false, note_form: note_form(socket.assigns.invoice))}
  end

  # --- Events: Billing Date ---

  @impl true
  def handle_event("save_billing_date", %{"billing_date" => val}, socket) do
    billing_date = normalize_month_to_date(val)

    case Invoices.update_billing_date(socket.assigns.invoice, %{billing_date: billing_date}) do
      {:ok, updated} ->
        reloaded = reload_details(updated, socket)

        {:noreply,
         socket
         |> put_flash(:info, "Billing period updated.")
         |> assign(invoice: reloaded, billing_date_form: billing_date_form(reloaded))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update billing period.")}
    end
  end

  # --- Events: Comments ---

  @impl true
  def handle_event("submit_comment", %{"body" => body}, socket) do
    case String.trim(body) do
      "" ->
        {:noreply, socket}

      trimmed ->
        user_id = socket.assigns.current_user.id
        invoice_id = socket.assigns.invoice.id
        company_id = socket.assigns.current_company.id

        case Invoices.create_invoice_comment(company_id, invoice_id, user_id, %{body: trimmed}) do
          {:ok, _comment} ->
            {:noreply,
             socket
             |> assign(
               comments: Invoices.list_invoice_comments(company_id, invoice_id),
               comment_form: comment_form(),
               comment_form_key: socket.assigns.comment_form_key + 1
             )}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to add comment.")}
        end
    end
  end

  @impl true
  def handle_event("edit_comment", %{"id" => comment_id}, socket) do
    comment = Enum.find(socket.assigns.comments, &(&1.id == comment_id))

    if comment && comment.user_id == socket.assigns.current_user.id do
      {:noreply,
       assign(socket,
         editing_comment_id: comment_id,
         edit_comment_form: to_form(%{"body" => comment.body})
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_comment_edit", %{"body" => body}, socket) do
    trimmed = String.trim(body)
    comment_id = socket.assigns.editing_comment_id
    comment = Enum.find(socket.assigns.comments, &(&1.id == comment_id))

    if trimmed == "" or is_nil(comment) or comment.user_id != socket.assigns.current_user.id do
      {:noreply, socket}
    else
      case Invoices.update_invoice_comment(comment, socket.assigns.current_user, %{body: trimmed}) do
        {:ok, _updated} ->
          {:noreply,
           socket
           |> assign(
             comments:
               Invoices.list_invoice_comments(
                 socket.assigns.current_company.id,
                 socket.assigns.invoice.id
               ),
             editing_comment_id: nil,
             edit_comment_form: nil
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to update comment.")}
      end
    end
  end

  @impl true
  def handle_event("cancel_comment_edit", _params, socket) do
    {:noreply, assign(socket, editing_comment_id: nil, edit_comment_form: nil)}
  end

  @impl true
  def handle_event("delete_comment", %{"id" => comment_id}, socket) do
    comment = Enum.find(socket.assigns.comments, &(&1.id == comment_id))

    if comment do
      case Invoices.delete_invoice_comment(comment, socket.assigns.current_user) do
        {:ok, _} ->
          {:noreply,
           assign(socket,
             comments:
               Invoices.list_invoice_comments(
                 socket.assigns.current_company.id,
                 socket.assigns.invoice.id
               )
           )}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete comment.")}
      end
    else
      {:noreply, socket}
    end
  end

  # --- Async: Re-extraction ---

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({ref, result}, %{assigns: %{extract_ref: ref}} = socket)
      when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(
           extracting: false,
           extract_ref: nil,
           invoice: reload_details(updated, socket),
           editing:
             Invoice.data_editable?(updated) and updated.extraction_status in [:partial, :failed]
         )
         |> assign_new_edit_form(updated)
         |> put_flash(:info, "Invoice data re-extracted successfully.")}

      {:error, :no_pdf} ->
        {:noreply,
         socket
         |> assign(extracting: false, extract_ref: nil)
         |> put_flash(:error, "No PDF file stored for this invoice.")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(extracting: false, extract_ref: nil)
         |> put_flash(:error, "Re-extraction failed. Please try again later.")}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{extract_ref: ref}} = socket)
      when is_reference(ref) do
    {:noreply,
     socket
     |> assign(extracting: false, extract_ref: nil)
     |> put_flash(:error, "Re-extraction crashed. Please try again.")}
  end

  def handle_info(msg, socket) do
    Logger.debug("InvoiceLive.Show received unexpected message: #{inspect(msg)}")
    {:noreply, socket}
  end

  # --- Private ---

  @spec note_form(Invoice.t()) :: Phoenix.HTML.Form.t()
  defp note_form(invoice) do
    to_form(%{"note" => invoice.note || ""})
  end

  @spec billing_date_form(Invoice.t()) :: Phoenix.HTML.Form.t()
  defp billing_date_form(invoice) do
    to_form(%{"billing_date" => invoice.billing_date})
  end

  @spec comment_form() :: Phoenix.HTML.Form.t()
  defp comment_form, do: to_form(%{"body" => ""})

  @spec assign_new_edit_form(Phoenix.LiveView.Socket.t(), Invoice.t()) ::
          Phoenix.LiveView.Socket.t()
  defp assign_new_edit_form(socket, invoice) do
    assign(socket, edit_form: build_edit_form(invoice))
  end

  @spec find_category(String.t() | nil, [map()]) :: map() | nil
  defp find_category(nil, _categories), do: nil
  defp find_category(id, categories), do: Enum.find(categories, &(&1.id == id))

  @spec reload_details(Invoice.t(), Phoenix.LiveView.Socket.t()) :: Invoice.t()
  defp reload_details(invoice, socket) do
    company_id = socket.assigns.current_company.id
    role = socket.assigns[:current_role]
    Invoices.get_invoice_with_details!(company_id, invoice.id, role: role)
  end

  @spec build_edit_form(Invoice.t()) :: Phoenix.HTML.Form.t()
  defp build_edit_form(invoice) do
    invoice
    |> Invoice.edit_changeset(%{})
    |> to_form(as: :invoice)
  end

  @spec relative_time(NaiveDateTime.t()) :: String.t()
  defp relative_time(naive_dt) do
    now = NaiveDateTime.utc_now()
    diff = NaiveDateTime.diff(now, naive_dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 2_592_000 -> "#{div(diff, 86_400)}d ago"
      true -> Calendar.strftime(naive_dt, "%Y-%m-%d")
    end
  end

  # --- Render ---

  @doc "Renders invoice detail page with metadata, edit form, preview, and action buttons."
  @impl true
  def render(assigns) do
    ~H"""
    <div class="breadcrumbs text-sm mb-2">
      <ul>
        <li><.link navigate={~p"/c/#{@current_company.id}/invoices"}>Invoices</.link></li>
        <li>{@invoice.invoice_number}</li>
      </ul>
    </div>

    <.header>
      Invoice {@invoice.invoice_number}
      <:subtitle>
        <.type_badge type={@invoice.type} />
        <.status_badge status={display_status(@invoice)} />
        <.needs_review_badge
          prediction_status={@invoice.prediction_status}
          duplicate_status={@invoice.duplicate_status}
          extraction_status={@invoice.extraction_status}
          status={@invoice.status}
        />
        <.extraction_badge status={@invoice.extraction_status} />
        <.payment_badge status={@payment_status} />
      </:subtitle>
      <:actions>
        <div class="flex gap-2">
          <div :if={@invoice.xml_file || @invoice.pdf_file} class="relative">
            <.button
              variant="outline"
              type="button"
              phx-click={JS.toggle(to: "#download-menu")}
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Download
              <.icon name="hero-chevron-down" class="size-3" />
            </.button>
            <div
              id="download-menu"
              class="hidden absolute right-0 top-full mt-1 z-50 p-1 border border-border bg-popover text-popover-foreground rounded-md shadow-md w-44"
              phx-click-away={JS.hide(to: "#download-menu")}
            >
              <a
                href={~p"/c/#{@current_company.id}/invoices/#{@invoice.id}/pdf"}
                target="_blank"
                class="flex items-center gap-2 px-2 py-1.5 text-sm rounded-sm text-muted-foreground hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors"
              >
                PDF
              </a>
              <a
                :if={@invoice.xml_file}
                href={~p"/c/#{@current_company.id}/invoices/#{@invoice.id}/xml"}
                target="_blank"
                class="flex items-center gap-2 px-2 py-1.5 text-sm rounded-sm text-muted-foreground hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors"
              >
                XML
              </a>
            </div>
          </div>
          <.button
            :if={@can_mutate}
            variant="outline"
            phx-click="copy_public_link"
            data-testid="copy-public-link"
            id="copy-link-btn"
          >
            <.icon name="hero-link" class="size-4" /> Share
          </.button>
          <.button
            :if={
              @can_approve && @invoice.type == :expense && @invoice.status == :pending &&
                @invoice.duplicate_status != :confirmed
            }
            variant="success"
            phx-click="approve"
          >
            Approve
          </.button>
          <.button
            :if={
              @can_approve && @invoice.type == :expense && @invoice.status == :pending &&
                @invoice.duplicate_status != :confirmed
            }
            variant="destructive"
            phx-click="reject"
          >
            Reject
          </.button>
        </div>
      </:actions>
    </.header>

    <div
      :if={@invoice.extraction_status in [:partial, :failed]}
      class="flex items-center gap-3 rounded-md border border-warning/20 bg-warning/5 p-4 mt-4"
      role="alert"
      data-testid="extraction-warning"
    >
      <.icon name="hero-exclamation-triangle" class="size-5" />
      <span :if={@data_editable}>
        This invoice has missing data. Please review and fill in the missing fields below.
      </span>
      <span :if={!@data_editable}>
        This invoice has missing data but cannot be edited because it originates from KSeF.
      </span>
      <.button
        :if={
          @data_editable && @can_mutate && @invoice.source in [:pdf_upload, :email] && !@extracting
        }
        variant="warning"
        phx-click="re_extract"
      >
        <.icon name="hero-arrow-path" class="size-4" /> Re-extract
      </.button>
      <span :if={@extracting} class="loading loading-spinner loading-sm" />
    </div>

    <div
      :if={@invoice.duplicate_of_id && @invoice.duplicate_status == :suspected}
      class="flex items-center gap-3 rounded-md border border-warning/20 bg-warning/5 p-4 mt-4"
      role="alert"
      data-testid="duplicate-warning"
    >
      <.icon name="hero-document-duplicate" class="size-5" />
      <span>
        This invoice may be a duplicate.
        <.link
          navigate={~p"/c/#{@current_company.id}/invoices/#{@invoice.duplicate_of_id}"}
          class="text-shad-primary underline-offset-4 hover:underline"
        >
          View original
        </.link>
      </span>
      <div :if={@can_mutate} class="flex-none flex gap-2">
        <.button variant="ghost" phx-click="dismiss_duplicate">
          Not a duplicate
        </.button>
        <.button variant="warning" phx-click="confirm_duplicate">
          Confirm duplicate
        </.button>
      </div>
    </div>
    <div
      :if={@invoice.duplicate_of_id && @invoice.duplicate_status == :confirmed}
      class="flex items-center gap-3 rounded-md border border-error/20 bg-error/5 p-4 mt-4"
      role="alert"
      data-testid="duplicate-confirmed"
    >
      <.icon name="hero-document-duplicate" class="size-5" />
      <span>
        This invoice is a confirmed duplicate of <.link
          navigate={~p"/c/#{@current_company.id}/invoices/#{@invoice.duplicate_of_id}"}
          class="text-shad-primary underline-offset-4 hover:underline"
        >
          the original
        </.link>.
      </span>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_minmax(0,2fr)] gap-6 mt-6">
      <!-- Invoice Metadata -->
      <div class="space-y-4">
        <.card padding="p-4">
          <div class="flex items-center justify-between mb-2">
            <div class="flex items-center gap-2">
              <h2 class="text-base font-semibold">Details</h2>
              <span
                :if={!@data_editable}
                class="inline-flex items-center gap-1 rounded-md bg-muted px-2 py-0.5 text-xs text-muted-foreground"
                data-testid="ksef-locked-badge"
              >
                <.icon name="hero-lock-closed" class="size-3" /> Data fields locked — KSeF invoice
              </span>
            </div>
            <.button
              :if={@can_mutate && @data_editable && !@editing}
              size="sm"
              variant="outline"
              phx-click="toggle_edit"
              data-testid="edit-details-btn"
            >
              <.icon name="hero-pencil-square" class="size-4" /> Edit
            </.button>
          </div>

          <div :if={@editing}>
            <.invoice_edit_form
              edit_form={@edit_form}
              invoice={@invoice}
              company={@current_company}
            />
          </div>
          <div :if={!@editing}>
            <.invoice_details_table invoice={@invoice} show_added_by={true} />
          </div>
        </.card>
        <!-- Category & Tags Card -->
        <.card padding="p-4">
          <div class="flex items-center justify-between mb-2">
            <h2 class="text-base font-semibold">Classification</h2>
            <.link
              :if={@can_set_category || @can_set_tags}
              navigate={~p"/c/#{@current_company.id}/invoices/#{@invoice.id}/classify"}
              data-testid="edit-classification"
              class="inline-flex items-center gap-1.5 rounded-md border border-input bg-background px-3 py-1.5 text-sm font-medium hover:bg-accent hover:text-accent-foreground"
            >
              <.icon name="hero-pencil-square" class="size-4" /> Edit
            </.link>
          </div>

          <div class="mb-3">
            <label class="text-sm text-muted-foreground">Category</label>
            <div class="mt-1" data-testid="category-display">
              <.category_badge category={find_category(@invoice.category_id, @categories)} />
            </div>
            <.prediction_hint
              predicted_at={@invoice.prediction_predicted_at}
              status={@invoice.prediction_status}
              confidence={@invoice.prediction_category_confidence}
              threshold={@confidence_threshold}
              label="category"
              testid="prediction-category-hint"
            />
          </div>

          <div>
            <label class="text-sm text-muted-foreground">Tags</label>
            <div class="mt-1" data-testid="tags-display">
              <.tag_list tags={@invoice.tags} />
            </div>
            <.prediction_hint
              predicted_at={@invoice.prediction_predicted_at}
              status={@invoice.prediction_status}
              confidence={@invoice.prediction_tag_confidence}
              threshold={@confidence_threshold}
              label="tag"
              testid="prediction-tag-hint"
            />
          </div>
        </.card>
        <!-- Billing Period Card -->
        <.card padding="p-4">
          <div class="flex items-center justify-between mb-2">
            <h2 class="text-base font-semibold">Billing Period</h2>
          </div>
          <div :if={!@can_mutate}>
            <span class="text-sm">
              {if @invoice.billing_date, do: format_month(@invoice.billing_date), else: "Not set"}
            </span>
          </div>
          <div :if={@can_mutate}>
            <.form
              for={@billing_date_form}
              phx-submit="save_billing_date"
              class="flex items-center gap-2"
            >
              <input
                type="month"
                name="billing_date"
                value={format_month_value(@billing_date_form[:billing_date].value)}
                class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
              />
              <.button type="submit" size="sm" variant="outline" class="shrink-0">
                Save
              </.button>
            </.form>
          </div>
        </.card>
        <!-- Note Card -->
        <.card padding="p-4">
          <div class="flex items-center justify-between mb-2">
            <h2 class="text-base font-semibold">Note</h2>
            <.button
              :if={@can_mutate && !@editing_note}
              variant="outline"
              size="sm"
              phx-click="edit_note"
            >
              <.icon name="hero-pencil-square" class="size-4" /> Edit
            </.button>
          </div>
          <div :if={@editing_note}>
            <.form for={@note_form} phx-submit="save_note" class="space-y-2">
              <textarea
                name={@note_form[:note].name}
                class="w-full rounded-md border border-input bg-background px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
                rows="8"
                placeholder="Add a note..."
                id="note-textarea"
                autofocus
              >{@note_form[:note].value}</textarea>
              <div class="flex gap-2">
                <.button type="submit" size="sm">
                  Save
                </.button>
                <.button type="button" variant="ghost" size="sm" phx-click="cancel_note">
                  Cancel
                </.button>
              </div>
            </.form>
          </div>
          <div
            :if={!@editing_note}
            class={[
              "text-sm rounded p-1 -m-1",
              @can_mutate && "cursor-pointer hover:bg-muted",
              !@invoice.note && "text-muted-foreground italic"
            ]}
            phx-click={if(@can_mutate, do: "edit_note")}
          >
            <span :if={@invoice.note} class="whitespace-pre-line">{@invoice.note}</span>
            <span :if={!@invoice.note}>No note</span>
          </div>
        </.card>
      </div>
      <!-- Preview -->
      <.card class="h-full" padding="p-4 flex flex-col h-full">
        <h2 class="text-base font-semibold mb-2">Preview</h2>
        <div
          :if={@html_preview}
          class="border border-border rounded-lg overflow-hidden flex-1 min-h-[600px]"
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
          class="border border-border rounded-lg overflow-hidden flex-1 min-h-[600px]"
        >
          <iframe
            src={~p"/c/#{@current_company.id}/invoices/#{@invoice.id}/pdf?inline=1"}
            class="w-full h-full bg-white"
            title="Invoice PDF preview"
          >
          </iframe>
        </div>
        <p
          :if={!@html_preview && !@invoice.pdf_file}
          class="text-muted-foreground text-sm"
        >
          No preview available. XML content may be missing.
        </p>
      </.card>
    </div>
    <!-- Payment Requests Section -->
    <div :if={@can_view_payment_requests && @invoice_payment_requests != []} class="mt-6">
      <div class="rounded-lg border border-border p-4">
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-base font-semibold">Payment Requests</h2>
          <.button
            :if={@can_manage_payment_requests && @invoice.type == :expense}
            size="sm"
            variant="outline"
            navigate={~p"/c/#{@current_company.id}/payment-requests/new?invoice_id=#{@invoice.id}"}
          >
            <.icon name="hero-plus" class="size-3.5" /> Add
          </.button>
        </div>
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b border-border">
              <th class="text-left py-2 px-2 text-xs font-medium text-muted-foreground uppercase">
                Recipient
              </th>
              <th class="text-left py-2 px-2 text-xs font-medium text-muted-foreground uppercase">
                Title
              </th>
              <th class="text-right py-2 px-2 text-xs font-medium text-muted-foreground uppercase">
                Amount
              </th>
              <th class="text-left py-2 px-2 text-xs font-medium text-muted-foreground uppercase">
                Status
              </th>
              <th class="text-left py-2 px-2 text-xs font-medium text-muted-foreground uppercase">
                Paid
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={pr <- @invoice_payment_requests}
              class="border-b border-border/50 last:border-0"
            >
              <td class="py-2 px-2">
                <.link
                  :if={@can_manage_payment_requests}
                  navigate={~p"/c/#{@current_company.id}/payment-requests/#{pr.id}/edit"}
                  class="text-shad-primary underline-offset-4 hover:underline"
                >
                  {pr.recipient_name}
                </.link>
                <span :if={!@can_manage_payment_requests}>{pr.recipient_name}</span>
              </td>
              <td class="py-2 px-2">{pr.title}</td>
              <td class="py-2 px-2 text-right font-mono">
                {format_amount(pr.amount)}
                <span class="text-xs text-muted-foreground">{pr.currency}</span>
              </td>
              <td class="py-2 px-2">
                <.payment_badge status={pr.status} />
              </td>
              <td class="py-2 px-2 text-xs">
                {if pr.paid_at, do: format_date(pr.paid_at), else: "-"}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Comments Section (below grid) -->
    <div class="mt-6">
      <.comments_card
        comments={@comments}
        comment_form={@comment_form}
        comment_form_key={@comment_form_key}
        editing_comment_id={@editing_comment_id}
        edit_comment_form={@edit_comment_form}
        current_user_id={@current_user.id}
      />
    </div>
    """
  end

  attr :comments, :list, required: true
  attr :comment_form, :map, required: true
  attr :comment_form_key, :integer, required: true
  attr :editing_comment_id, :string, default: nil
  attr :edit_comment_form, :map, default: nil
  attr :current_user_id, :string, required: true

  @spec comments_card(map()) :: Phoenix.LiveView.Rendered.t()
  defp comments_card(assigns) do
    ~H"""
    <.card padding="p-4">
      <h2 class="text-base font-semibold mb-2">Comments</h2>

      <div :if={@comments == []} class="text-sm text-muted-foreground italic">
        No comments yet
      </div>

      <div :if={@comments != []} class="text-sm space-y-0.5 mb-3">
        <div :for={comment <- @comments} class="group" id={"comment-#{comment.id}"}>
          <%!-- Header: name · time · actions --%>
          <div class="flex items-baseline gap-1.5 leading-snug">
            <span class="font-medium">{comment.user.name || comment.user.email}</span>
            <span class="text-xs text-muted-foreground">{relative_time(comment.inserted_at)}</span>
            <div
              :if={comment.user_id == @current_user_id}
              class="opacity-0 group-hover:opacity-100 focus-within:opacity-100 transition-opacity inline-flex gap-0.5 ml-0.5"
            >
              <button
                phx-click="edit_comment"
                phx-value-id={comment.id}
                class="text-muted-foreground hover:text-foreground"
                aria-label="Edit comment"
              >
                <.icon name="hero-pencil-square" class="size-3" />
              </button>
              <button
                phx-click="delete_comment"
                phx-value-id={comment.id}
                data-confirm="Delete this comment?"
                class="text-shad-destructive/60 hover:text-shad-destructive"
                aria-label="Delete comment"
              >
                <.icon name="hero-trash" class="size-3" />
              </button>
            </div>
          </div>
          <%!-- Body or edit form --%>
          <div :if={@editing_comment_id == comment.id} class="mt-1">
            <.form for={@edit_comment_form} phx-submit="save_comment_edit">
              <textarea
                name={@edit_comment_form[:body].name}
                class="w-full rounded-md border border-input bg-background px-2 py-1 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring resize-none"
                style="field-sizing: content"
                rows="1"
                oninput="this.style.height='auto';this.style.height=this.scrollHeight+'px'"
              >{@edit_comment_form[:body].value}</textarea>
              <div class="flex gap-2 mt-1">
                <.button type="submit" size="sm">Save</.button>
                <.button type="button" variant="ghost" size="sm" phx-click="cancel_comment_edit">
                  Cancel
                </.button>
              </div>
            </.form>
          </div>
          <div
            :if={@editing_comment_id != comment.id}
            class="whitespace-pre-wrap text-muted-foreground"
          >
            {comment.body}
          </div>
        </div>
      </div>

      <.form
        for={@comment_form}
        phx-submit="submit_comment"
        id={"comment-form-#{@comment_form_key}"}
        class="flex items-end gap-2 mt-2"
      >
        <textarea
          name={@comment_form[:body].name}
          placeholder="Add a comment..."
          rows="1"
          class="w-full rounded-md border border-input bg-background px-2 py-1 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring flex-1 resize-none"
          style="field-sizing: content"
          oninput="this.style.height='auto';this.style.height=this.scrollHeight+'px'"
        >{@comment_form[:body].value}</textarea>
        <.button type="submit" size="sm">Post</.button>
      </.form>
    </.card>
    """
  end

  attr :edit_form, :map, required: true
  attr :invoice, :map, required: true
  attr :company, :map, required: true

  @spec invoice_edit_form(map()) :: Phoenix.LiveView.Rendered.t()
  defp invoice_edit_form(assigns) do
    ~H"""
    <.form
      for={@edit_form}
      id="edit-invoice-form"
      phx-change="validate_edit"
      phx-submit="save_edit"
      class="space-y-3"
    >
      <.buyer_fields
        edit_form={@edit_form}
        readonly={@invoice.type == :expense}
        company={@company}
      />
      <.seller_fields
        edit_form={@edit_form}
        readonly={@invoice.type == :income}
        company={@company}
      />

      <div class="border-t border-border my-4 text-xs my-1">Invoice</div>

      <div class="grid grid-cols-3 gap-3">
        <div class="space-y-1">
          <label for="edit-invoice-number" class="label">
            <span class="text-sm font-medium text-xs">Invoice Number</span>
          </label>
          <input
            type="text"
            id="edit-invoice-number"
            name={@edit_form[:invoice_number].name}
            value={@edit_form[:invoice_number].value}
            class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          />
          <.field_error errors={@edit_form[:invoice_number].errors} />
        </div>

        <div class="space-y-1">
          <label for="edit-issue-date" class="label">
            <span class="text-sm font-medium text-xs">Issue Date</span>
          </label>
          <input
            type="date"
            id="edit-issue-date"
            name={@edit_form[:issue_date].name}
            value={@edit_form[:issue_date].value}
            class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          />
          <.field_error errors={@edit_form[:issue_date].errors} />
        </div>

        <div class="space-y-1">
          <label for="edit-sales-date" class="label">
            <span class="text-sm font-medium text-xs">Sales Date</span>
          </label>
          <input
            type="date"
            id="edit-sales-date"
            name={@edit_form[:sales_date].name}
            value={@edit_form[:sales_date].value}
            class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          />
          <.field_error errors={@edit_form[:sales_date].errors} />
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div class="space-y-1">
          <label for="edit-due-date" class="label">
            <span class="text-sm font-medium text-xs">Due Date</span>
          </label>
          <input
            type="date"
            id="edit-due-date"
            name={@edit_form[:due_date].name}
            value={@edit_form[:due_date].value}
            class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          />
          <.field_error errors={@edit_form[:due_date].errors} />
        </div>

        <div class="space-y-1">
          <label for="edit-billing-date" class="label">
            <span class="text-sm font-medium text-xs">Billing Period</span>
          </label>
          <input
            type="month"
            id="edit-billing-date"
            name={@edit_form[:billing_date].name}
            value={format_month_value(@edit_form[:billing_date].value)}
            class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          />
          <.field_error errors={@edit_form[:billing_date].errors} />
        </div>
      </div>

      <.amount_fields edit_form={@edit_form} />

      <div class="space-y-1 mt-3">
        <label for="edit-purchase-order" class="label">
          <span class="text-sm font-medium text-xs">Purchase Order</span>
        </label>
        <input
          type="text"
          id="edit-purchase-order"
          name={@edit_form[:purchase_order].name}
          value={@edit_form[:purchase_order].value}
          class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          maxlength="256"
          placeholder="e.g. PO-2025-001"
        />
        <.field_error errors={@edit_form[:purchase_order].errors} />
      </div>

      <div class="space-y-1 mt-3">
        <label for="edit-iban" class="label">
          <span class="text-sm font-medium text-xs">IBAN</span>
        </label>
        <input
          type="text"
          id="edit-iban"
          name={@edit_form[:iban].name}
          value={@edit_form[:iban].value}
          class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring font-mono"
          maxlength="34"
          placeholder="e.g. PL61109010140000071219812874"
        />
        <.field_error errors={@edit_form[:iban].errors} />
      </div>

      <.address_fields edit_form={@edit_form} field={:seller_address} label="Seller Address" />
      <.address_fields edit_form={@edit_form} field={:buyer_address} label="Buyer Address" />

      <div class="flex gap-2 pt-2">
        <.button type="submit">Save</.button>
        <.button variant="ghost" type="button" phx-click="cancel_edit">Cancel</.button>
      </div>
    </.form>
    """
  end

  attr :edit_form, :map, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true

  @spec address_fields(map()) :: Phoenix.LiveView.Rendered.t()
  defp address_fields(assigns) do
    addr = assigns.edit_form[assigns.field].value |> stringify_keys()
    prefix = "invoice[#{assigns.field}]"

    assigns =
      assign(assigns,
        addr: addr,
        prefix: prefix,
        field_id: assigns.field |> Atom.to_string() |> String.replace("_", "-")
      )

    ~H"""
    <div class="border-t border-border my-4 text-xs my-1">{@label}</div>

    <div class="space-y-1">
      <label for={"edit-#{@field_id}-street"} class="label">
        <span class="text-sm font-medium text-xs">Street</span>
      </label>
      <input
        type="text"
        id={"edit-#{@field_id}-street"}
        name={"#{@prefix}[street]"}
        value={@addr["street"]}
        class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
      />
    </div>

    <div class="grid grid-cols-2 gap-3">
      <div class="space-y-1">
        <label for={"edit-#{@field_id}-city"} class="label">
          <span class="text-sm font-medium text-xs">City</span>
        </label>
        <input
          type="text"
          id={"edit-#{@field_id}-city"}
          name={"#{@prefix}[city]"}
          value={@addr["city"]}
          class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
        />
      </div>

      <div class="space-y-1">
        <label for={"edit-#{@field_id}-postal-code"} class="label">
          <span class="text-sm font-medium text-xs">Postal Code</span>
        </label>
        <input
          type="text"
          id={"edit-#{@field_id}-postal-code"}
          name={"#{@prefix}[postal_code]"}
          value={@addr["postal_code"]}
          class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
        />
      </div>
    </div>

    <div class="space-y-1">
      <label for={"edit-#{@field_id}-country"} class="label">
        <span class="text-sm font-medium text-xs">Country</span>
      </label>
      <input
        type="text"
        id={"edit-#{@field_id}-country"}
        name={"#{@prefix}[country]"}
        value={@addr["country"]}
        class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
        maxlength="10"
      />
    </div>
    """
  end

  @spec stringify_keys(map() | nil) :: map()
  defp stringify_keys(nil), do: %{}
  defp stringify_keys(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  attr :edit_form, :map, required: true
  attr :readonly, :boolean, default: false
  attr :company, :map, required: true

  @spec seller_fields(map()) :: Phoenix.LiveView.Rendered.t()
  defp seller_fields(assigns) do
    ~H"""
    <div class="border-t border-border my-4 text-xs my-1">Seller</div>

    <div class="grid grid-cols-2 gap-3">
      <div class="space-y-1">
        <label for="edit-seller-name" class="label">
          <span class="text-sm font-medium text-xs">Name</span>
        </label>
        <input
          :if={@readonly}
          type="text"
          id="edit-seller-name"
          value={@company.name}
          class="h-9 w-full rounded-md border border-input bg-muted px-3 text-sm text-muted-foreground"
          disabled
        />
        <input
          :if={!@readonly}
          type="text"
          id="edit-seller-name"
          name={@edit_form[:seller_name].name}
          value={@edit_form[:seller_name].value}
          class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
        />
        <.field_error :if={!@readonly} errors={@edit_form[:seller_name].errors} />
      </div>

      <div class="space-y-1">
        <label for="edit-seller-nip" class="label">
          <span class="text-sm font-medium text-xs">NIP</span>
        </label>
        <input
          :if={@readonly}
          type="text"
          id="edit-seller-nip"
          value={@company.nip}
          class="h-9 w-full rounded-md border border-input bg-muted px-3 text-sm text-muted-foreground"
          disabled
        />
        <input
          :if={!@readonly}
          type="text"
          id="edit-seller-nip"
          name={@edit_form[:seller_nip].name}
          value={@edit_form[:seller_nip].value}
          class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          maxlength="50"
        />
        <.field_error :if={!@readonly} errors={@edit_form[:seller_nip].errors} />
      </div>
    </div>
    """
  end

  attr :edit_form, :map, required: true
  attr :readonly, :boolean, default: false
  attr :company, :map, required: true

  @spec buyer_fields(map()) :: Phoenix.LiveView.Rendered.t()
  defp buyer_fields(assigns) do
    ~H"""
    <div class="border-t border-border my-4 text-xs my-1">Buyer</div>

    <div class="grid grid-cols-2 gap-3">
      <div class="space-y-1">
        <label for="edit-buyer-name" class="label">
          <span class="text-sm font-medium text-xs">Name</span>
        </label>
        <input
          :if={@readonly}
          type="text"
          id="edit-buyer-name"
          value={@company.name}
          class="h-9 w-full rounded-md border border-input bg-muted px-3 text-sm text-muted-foreground"
          disabled
        />
        <input
          :if={!@readonly}
          type="text"
          id="edit-buyer-name"
          name={@edit_form[:buyer_name].name}
          value={@edit_form[:buyer_name].value}
          class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
        />
        <.field_error :if={!@readonly} errors={@edit_form[:buyer_name].errors} />
      </div>

      <div class="space-y-1">
        <label for="edit-buyer-nip" class="label">
          <span class="text-sm font-medium text-xs">NIP</span>
        </label>
        <input
          :if={@readonly}
          type="text"
          id="edit-buyer-nip"
          value={@company.nip}
          class="h-9 w-full rounded-md border border-input bg-muted px-3 text-sm text-muted-foreground"
          disabled
        />
        <input
          :if={!@readonly}
          type="text"
          id="edit-buyer-nip"
          name={@edit_form[:buyer_nip].name}
          value={@edit_form[:buyer_nip].value}
          class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          maxlength="50"
        />
        <.field_error :if={!@readonly} errors={@edit_form[:buyer_nip].errors} />
      </div>
    </div>
    """
  end

  attr :edit_form, :map, required: true

  @spec amount_fields(map()) :: Phoenix.LiveView.Rendered.t()
  defp amount_fields(assigns) do
    ~H"""
    <div class="border-t border-border my-4 text-xs my-1">Amounts</div>

    <div class="grid grid-cols-3 gap-3">
      <div class="space-y-1">
        <label for="edit-net-amount" class="label">
          <span class="text-sm font-medium text-xs">Netto</span>
        </label>
        <input
          type="text"
          inputmode="decimal"
          id="edit-net-amount"
          name={@edit_form[:net_amount].name}
          value={@edit_form[:net_amount].value}
          class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring font-mono"
        />
        <.field_error errors={@edit_form[:net_amount].errors} />
      </div>

      <div class="space-y-1">
        <label for="edit-gross-amount" class="label">
          <span class="text-sm font-medium text-xs">Brutto</span>
        </label>
        <input
          type="text"
          inputmode="decimal"
          id="edit-gross-amount"
          name={@edit_form[:gross_amount].name}
          value={@edit_form[:gross_amount].value}
          class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring font-mono"
        />
        <.field_error errors={@edit_form[:gross_amount].errors} />
      </div>

      <div class="space-y-1">
        <label for="edit-currency" class="label">
          <span class="text-sm font-medium text-xs">Currency</span>
        </label>
        <select
          id="edit-currency"
          name={@edit_form[:currency].name}
          class="h-9 rounded-md border border-input bg-background px-2 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring w-full"
        >
          <option
            :for={code <- currencies()}
            value={code}
            selected={@edit_form[:currency].value == code}
          >
            {code}
          </option>
        </select>
        <.field_error errors={@edit_form[:currency].errors} />
      </div>
    </div>
    """
  end

  @common_currencies ~w(PLN EUR USD GBP CHF CZK SEK NOK DKK HUF RON BGN HRK TRY UAH RUB JPY CNY CAD AUD NZD BRL MXN INR KRW SGD HKD THB ZAR ILS AED SAR)

  @spec currencies() :: [String.t()]
  defp currencies, do: @common_currencies

  @spec format_month_value(Date.t() | nil) :: String.t() | nil
  defp format_month_value(%Date{year: y, month: m}),
    do: "#{y}-#{String.pad_leading(Integer.to_string(m), 2, "0")}"

  defp format_month_value(_), do: nil

  @spec normalize_month_to_date(String.t()) :: String.t()
  defp normalize_month_to_date(val) when is_binary(val) do
    case Regex.run(~r/^(\d{4})-(\d{2})$/, val) do
      [_, year, month] -> "#{year}-#{month}-01"
      _ -> val
    end
  end

  @spec normalize_billing_date_param(map()) :: map()
  defp normalize_billing_date_param(%{"billing_date" => val} = params) when is_binary(val) do
    case Regex.run(~r/^(\d{4})-(\d{2})$/, val) do
      [_, year, month] -> Map.put(params, "billing_date", "#{year}-#{month}-01")
      _ -> params
    end
  end

  defp normalize_billing_date_param(params), do: params

  attr :errors, :list, default: []

  @spec field_error(map()) :: Phoenix.LiveView.Rendered.t()
  defp field_error(assigns) do
    ~H"""
    <p :for={{msg, _opts} <- @errors} class="text-xs text-shad-destructive mt-0.5">{msg}</p>
    """
  end
end
