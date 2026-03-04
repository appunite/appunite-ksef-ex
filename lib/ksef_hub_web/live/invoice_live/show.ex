defmodule KsefHubWeb.InvoiceLive.Show do
  @moduledoc """
  LiveView for invoice detail page with HTML preview, metadata,
  category/tag editing, edit form, and approve/reject actions.
  """
  use KsefHubWeb, :live_view

  require Logger

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice

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
        auto_edit = invoice.extraction_status in [:partial, :failed]

        {:ok,
         socket
         |> assign(
           page_title: "Invoice #{invoice.invoice_number}",
           invoice: invoice,
           html_preview: generate_preview(invoice),
           categories: Invoices.list_categories(company.id),
           all_tags: Invoices.list_tags(company.id),
           category_form: category_form(invoice),
           new_tag_form: new_tag_form(),
           tag_form_key: 0,
           editing: auto_edit,
           edit_form: build_edit_form(invoice),
           editing_note: false,
           note_form: note_form(invoice),
           comments: Invoices.list_invoice_comments(company.id, invoice.id),
           comment_form: comment_form(),
           extracting: false,
           extract_ref: nil,
           comment_form_key: 0,
           editing_comment_id: nil,
           edit_comment_form: nil
         )}
    end
  end

  # --- Events: Re-extract ---

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
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

  # --- Events: Category ---

  @impl true
  def handle_event("set_category", %{"category_id" => raw_id}, socket) do
    category_id = if raw_id == "", do: nil, else: raw_id

    with :ok <- validate_category_id(category_id),
         {:ok, updated} <- Invoices.set_invoice_category(socket.assigns.invoice, category_id) do
      reloaded = reload_details(updated, socket)

      case Invoices.mark_prediction_manual(updated) do
        {:ok, _} ->
          {:noreply, assign(socket, invoice: reloaded, category_form: category_form(reloaded))}

        {:error, _} ->
          {:noreply,
           socket
           |> assign(invoice: reloaded, category_form: category_form(reloaded))
           |> put_flash(:warning, "Category saved but prediction status update failed.")}
      end
    else
      {:error, :invalid_id} ->
        {:noreply, put_flash(socket, :error, "Invalid category.")}

      {:error, :category_not_in_company} ->
        {:noreply, put_flash(socket, :error, "Category not found.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update category.")}
    end
  end

  # --- Events: Tags ---

  @impl true
  def handle_event("toggle_tag", %{"tag-id" => tag_id}, socket) do
    if Enum.any?(socket.assigns.all_tags, &(&1.id == tag_id)) do
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
    else
      {:noreply, put_flash(socket, :error, "Invalid tag.")}
    end
  end

  @impl true
  def handle_event("create_and_add_tag", %{"name" => name}, socket) do
    case String.trim(name) do
      "" -> {:noreply, socket}
      trimmed -> do_create_and_add_tag(socket, trimmed)
    end
  end

  # --- Events: Edit ---

  @impl true
  def handle_event("toggle_edit", _params, socket) do
    {:noreply,
     assign(socket,
       editing: true,
       edit_form: build_edit_form(socket.assigns.invoice)
     )}
  end

  @impl true
  def handle_event("validate_edit", %{"invoice" => params}, socket) do
    changeset =
      socket.assigns.invoice
      |> Invoice.edit_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, edit_form: to_form(changeset, as: :invoice))}
  end

  @impl true
  def handle_event("save_edit", %{"invoice" => params}, socket) do
    case Invoices.update_invoice_fields(socket.assigns.invoice, params) do
      {:ok, updated} ->
        reloaded = reload_details(updated, socket)

        {:noreply,
         socket
         |> put_flash(:info, "Invoice updated.")
         |> assign(
           invoice: reloaded,
           editing: false,
           edit_form: build_edit_form(reloaded)
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
           editing: updated.extraction_status in [:partial, :failed]
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

  @spec do_create_and_add_tag(Phoenix.LiveView.Socket.t(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_create_and_add_tag(socket, name) do
    company_id = socket.assigns.current_company.id
    invoice = socket.assigns.invoice

    case Invoices.create_and_add_tag(invoice.id, company_id, %{name: name}) do
      {:ok, _tag} ->
        {:noreply,
         socket
         |> assign(
           invoice: reload_details(invoice, socket),
           all_tags: Invoices.list_tags(company_id),
           new_tag_form: new_tag_form(),
           tag_form_key: socket.assigns.tag_form_key + 1
         )}

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

  @spec category_form(Invoice.t()) :: Phoenix.HTML.Form.t()
  defp category_form(invoice) do
    to_form(%{"category_id" => invoice.category_id || ""})
  end

  @spec note_form(Invoice.t()) :: Phoenix.HTML.Form.t()
  defp note_form(invoice) do
    to_form(%{"note" => invoice.note || ""})
  end

  @spec comment_form() :: Phoenix.HTML.Form.t()
  defp comment_form, do: to_form(%{"body" => ""})

  @spec new_tag_form() :: Phoenix.HTML.Form.t()
  defp new_tag_form, do: to_form(%{"name" => ""})

  @spec validate_category_id(String.t() | nil) :: :ok | {:error, :invalid_id}
  defp validate_category_id(nil), do: :ok

  defp validate_category_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _} -> :ok
      :error -> {:error, :invalid_id}
    end
  end

  @spec assign_new_edit_form(Phoenix.LiveView.Socket.t(), Invoice.t()) ::
          Phoenix.LiveView.Socket.t()
  defp assign_new_edit_form(socket, invoice) do
    assign(socket, edit_form: build_edit_form(invoice))
  end

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

  @spec generate_preview(Invoice.t()) :: String.t() | nil
  defp generate_preview(invoice) do
    if invoice.xml_file do
      pdf_mod = Application.get_env(:ksef_hub, :pdf_renderer, KsefHub.PdfRenderer)

      metadata = %{ksef_number: invoice.ksef_number}

      case pdf_mod.generate_html(invoice.xml_file.content, metadata) do
        {:ok, html} -> html
        {:error, _} -> nil
      end
    end
  end

  @spec tag_assigned?(Invoice.t(), String.t()) :: boolean()
  defp tag_assigned?(invoice, tag_id) do
    Enum.any?(invoice.tags, &(&1.id == tag_id))
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
        <.status_badge status={@invoice.status} />
        <.needs_review_badge
          prediction_status={@invoice.prediction_status}
          duplicate_status={@invoice.duplicate_status}
          extraction_status={@invoice.extraction_status}
          status={@invoice.status}
        />
        <.extraction_badge status={@invoice.extraction_status} />
      </:subtitle>
      <:actions>
        <div class="flex gap-2">
          <div :if={@invoice.xml_file || @invoice.pdf_file} class="dropdown dropdown-end">
            <div tabindex="0" role="button" class="btn btn-sm btn-outline">
              <.icon name="hero-arrow-down-tray" class="size-4" /> Download
              <.icon name="hero-chevron-down" class="size-3" />
            </div>
            <ul
              tabindex="0"
              class="dropdown-content z-50 menu p-2 border border-base-300 bg-base-100 rounded-box w-44"
            >
              <li>
                <a href={~p"/c/#{@current_company.id}/invoices/#{@invoice.id}/pdf"}>PDF</a>
              </li>
              <li :if={@invoice.xml_file}>
                <a href={~p"/c/#{@current_company.id}/invoices/#{@invoice.id}/xml"}>XML</a>
              </li>
            </ul>
          </div>
          <button
            :if={!@editing}
            phx-click="toggle_edit"
            class="btn btn-sm btn-outline"
          >
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </button>
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

    <div
      :if={@invoice.extraction_status in [:partial, :failed]}
      class="alert alert-warning mt-4"
      role="alert"
      data-testid="extraction-warning"
    >
      <.icon name="hero-exclamation-triangle" class="size-5" />
      <span>
        This invoice has missing data. Please review and fill in the missing fields below.
      </span>
      <button
        :if={@invoice.source in [:pdf_upload, :email] and not @extracting}
        phx-click="re_extract"
        class="btn btn-sm btn-warning"
      >
        <.icon name="hero-arrow-path" class="size-4" /> Re-extract
      </button>
      <span :if={@extracting} class="loading loading-spinner loading-sm" />
    </div>

    <div
      :if={@invoice.duplicate_of_id && @invoice.duplicate_status == :suspected}
      class="alert alert-warning mt-4"
      role="alert"
      data-testid="duplicate-warning"
    >
      <.icon name="hero-document-duplicate" class="size-5" />
      <span>
        This invoice may be a duplicate.
        <.link
          navigate={~p"/c/#{@current_company.id}/invoices/#{@invoice.duplicate_of_id}"}
          class="link link-primary"
        >
          View original
        </.link>
      </span>
      <div class="flex-none flex gap-2">
        <button phx-click="dismiss_duplicate" class="btn btn-sm btn-ghost">
          Not a duplicate
        </button>
        <button phx-click="confirm_duplicate" class="btn btn-sm btn-warning">
          Confirm duplicate
        </button>
      </div>
    </div>
    <div
      :if={@invoice.duplicate_of_id && @invoice.duplicate_status == :confirmed}
      class="alert alert-error mt-4"
      role="alert"
      data-testid="duplicate-confirmed"
    >
      <.icon name="hero-document-duplicate" class="size-5" />
      <span>
        This invoice is a confirmed duplicate of <.link
          navigate={~p"/c/#{@current_company.id}/invoices/#{@invoice.duplicate_of_id}"}
          class="link link-primary"
        >
          the original
        </.link>.
      </span>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_minmax(0,2fr)] gap-6 mt-6">
      <!-- Invoice Metadata -->
      <div class="space-y-4">
        <div class="card bg-base-100 border border-base-300">
          <div class="p-4">
            <h2 class="text-base font-semibold mb-2">Details</h2>

            <%= if @editing do %>
              <.invoice_edit_form
                edit_form={@edit_form}
                invoice={@invoice}
                company={@current_company}
              />
            <% else %>
              <table class="text-sm w-full">
                <tbody>
                  <tr class="border-b border-base-300/50">
                    <td class="py-1.5 pr-3 text-base-content/60">Buyer</td>
                    <td class="py-1.5 text-right">
                      <div>{@invoice.buyer_name}</div>
                      <div class="text-xs text-base-content/50">{@invoice.buyer_nip}</div>
                    </td>
                  </tr>
                  <tr class="border-b border-base-300/50">
                    <td class="py-1.5 pr-3 text-base-content/60">Seller</td>
                    <td class="py-1.5 text-right">
                      <div>{@invoice.seller_name}</div>
                      <div class="text-xs text-base-content/50">{@invoice.seller_nip}</div>
                    </td>
                  </tr>
                  <tr class="border-b border-base-300/50">
                    <td class="py-1.5 pr-3 text-base-content/60 whitespace-nowrap">Number</td>
                    <td class="py-1.5 text-right">{@invoice.invoice_number}</td>
                  </tr>
                  <tr class="border-b border-base-300/50">
                    <td class="py-1.5 pr-3 text-base-content/60">Date</td>
                    <td class="py-1.5 text-right">{format_date(@invoice.issue_date)}</td>
                  </tr>
                  <tr class={[
                    "border-b border-base-300/50",
                    is_nil(@invoice.net_amount) && "bg-warning/5"
                  ]}>
                    <td class="py-1.5 pr-3 text-base-content/60">Netto</td>
                    <td class="py-1.5 text-right font-mono">
                      {format_amount(@invoice.net_amount)} {@invoice.currency}
                    </td>
                  </tr>
                  <tr class={[
                    "border-b border-base-300/50",
                    is_nil(@invoice.gross_amount) && "bg-warning/5"
                  ]}>
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
                  <tr :if={@invoice.purchase_order} class="border-b border-base-300/50">
                    <td class="py-1.5 pr-3 text-base-content/60 whitespace-nowrap">PO</td>
                    <td class="py-1.5 text-right font-mono text-sm break-all">
                      {@invoice.purchase_order}
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
            <% end %>
          </div>
        </div>
        <!-- Category & Tags Card -->
        <div class="card bg-base-100 border border-base-300">
          <div class="p-4">
            <h2 class="text-base font-semibold mb-3">Classification</h2>
            <!-- Category Select -->
            <.form
              for={@category_form}
              phx-change="set_category"
              data-testid="category-form"
              class="mb-4"
            >
              <label class="label"><span class="label-text text-xs">Category</span></label>
              <select
                name={@category_form[:category_id].name}
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
            </.form>
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
              <.form
                for={@new_tag_form}
                phx-submit="create_and_add_tag"
                id={"new-tag-form-#{@tag_form_key}"}
                class="flex gap-2 mt-2"
              >
                <input
                  type="text"
                  name={@new_tag_form[:name].name}
                  value={@new_tag_form[:name].value}
                  placeholder="New tag..."
                  class="input input-xs input-bordered flex-1"
                  data-testid="new-tag-input"
                />
                <button type="submit" class="btn btn-xs btn-primary">Add</button>
              </.form>
            </div>
          </div>
        </div>
        <!-- Note Card -->
        <div class="card bg-base-100 border border-base-300">
          <div class="p-4">
            <div class="flex items-center justify-between mb-2">
              <h2 class="text-base font-semibold">Note</h2>
              <button
                :if={!@editing_note}
                phx-click="edit_note"
                class="btn btn-xs btn-ghost"
                aria-label="Edit note"
              >
                <.icon name="hero-pencil-square" class="size-3.5" />
              </button>
            </div>
            <%= if @editing_note do %>
              <.form for={@note_form} phx-submit="save_note" class="space-y-2">
                <textarea
                  name={@note_form[:note].name}
                  class="textarea textarea-bordered w-full text-sm"
                  rows="8"
                  placeholder="Add a note..."
                  id="note-textarea"
                  autofocus
                >{@note_form[:note].value}</textarea>
                <div class="flex gap-2">
                  <button type="submit" class="btn btn-xs btn-primary">Save</button>
                  <button type="button" phx-click="cancel_note" class="btn btn-xs btn-ghost">
                    Cancel
                  </button>
                </div>
              </.form>
            <% else %>
              <div
                class={[
                  "text-sm cursor-pointer hover:bg-base-200 rounded p-1 -m-1",
                  !@invoice.note && "text-base-content/40 italic"
                ]}
                phx-click="edit_note"
              >
                <span :if={@invoice.note} class="whitespace-pre-line">{@invoice.note}</span>
                <span :if={!@invoice.note}>No note</span>
              </div>
            <% end %>
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
              src={~p"/c/#{@current_company.id}/invoices/#{@invoice.id}/pdf?inline=1"}
              class="w-full h-full bg-white"
              title="Invoice PDF preview"
            >
            </iframe>
          </div>
          <p
            :if={!@html_preview && !@invoice.pdf_file}
            class="text-base-content/60 text-sm"
          >
            No preview available. XML content may be missing.
          </p>
        </div>
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
    <div class="card bg-base-100 border border-base-300">
      <div class="p-4">
        <h2 class="text-base font-semibold mb-3">Comments</h2>

        <div :if={@comments == []} class="text-sm text-base-content/40 italic mb-3">
          No comments yet
        </div>

        <div class="space-y-3 mb-3">
          <div :for={comment <- @comments} class="group" id={"comment-#{comment.id}"}>
            <div class="flex items-start gap-2">
              <div class="avatar placeholder">
                <div class="bg-neutral text-neutral-content rounded-full w-7 h-7">
                  <span class="text-xs">
                    {comment.user.name
                    |> to_string()
                    |> String.first()
                    |> to_string()
                    |> String.upcase()}
                  </span>
                </div>
              </div>
              <div class="flex-1 min-w-0">
                <div class="flex items-baseline gap-2">
                  <span class="text-sm font-medium">{comment.user.name || comment.user.email}</span>
                  <span class="text-xs text-base-content/40">
                    {relative_time(comment.inserted_at)}
                  </span>
                  <div
                    :if={comment.user_id == @current_user_id}
                    class="opacity-0 group-hover:opacity-100 focus-within:opacity-100 transition-opacity ml-auto flex gap-1"
                  >
                    <button
                      phx-click="edit_comment"
                      phx-value-id={comment.id}
                      class="btn btn-xs btn-ghost"
                      aria-label="Edit comment"
                    >
                      <.icon name="hero-pencil-square" class="size-3" />
                    </button>
                    <button
                      phx-click="delete_comment"
                      phx-value-id={comment.id}
                      data-confirm="Delete this comment?"
                      class="btn btn-xs btn-ghost text-error"
                      aria-label="Delete comment"
                    >
                      <.icon name="hero-trash" class="size-3" />
                    </button>
                  </div>
                </div>

                <%= if @editing_comment_id == comment.id do %>
                  <.form for={@edit_comment_form} phx-submit="save_comment_edit" class="mt-1">
                    <textarea
                      name={@edit_comment_form[:body].name}
                      class="textarea textarea-bordered textarea-sm w-full"
                      rows="2"
                    >{@edit_comment_form[:body].value}</textarea>
                    <div class="flex gap-2 mt-1">
                      <button type="submit" class="btn btn-xs btn-primary">Save</button>
                      <button
                        type="button"
                        phx-click="cancel_comment_edit"
                        class="btn btn-xs btn-ghost"
                      >
                        Cancel
                      </button>
                    </div>
                  </.form>
                <% else %>
                  <p class="text-sm whitespace-pre-wrap mt-0.5">{comment.body}</p>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <.form
          for={@comment_form}
          phx-submit="submit_comment"
          id={"comment-form-#{@comment_form_key}"}
          class="flex gap-2"
        >
          <input
            type="text"
            name={@comment_form[:body].name}
            value={@comment_form[:body].value}
            placeholder="Add a comment..."
            class="input input-sm input-bordered flex-1"
          />
          <button type="submit" class="btn btn-sm btn-primary">Post</button>
        </.form>
      </div>
    </div>
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

      <div class="divider text-xs my-1">Invoice</div>

      <div class="grid grid-cols-2 gap-3">
        <div class="form-control">
          <label for="edit-invoice-number" class="label">
            <span class="label-text text-xs">Invoice Number</span>
          </label>
          <input
            type="text"
            id="edit-invoice-number"
            name={@edit_form[:invoice_number].name}
            value={@edit_form[:invoice_number].value}
            class="input input-sm input-bordered w-full"
          />
          <.field_error errors={@edit_form[:invoice_number].errors} />
        </div>

        <div class="form-control">
          <label for="edit-issue-date" class="label">
            <span class="label-text text-xs">Issue Date</span>
          </label>
          <input
            type="date"
            id="edit-issue-date"
            name={@edit_form[:issue_date].name}
            value={@edit_form[:issue_date].value}
            class="input input-sm input-bordered w-full"
          />
          <.field_error errors={@edit_form[:issue_date].errors} />
        </div>
      </div>

      <.amount_fields edit_form={@edit_form} />

      <div class="form-control mt-3">
        <label for="edit-purchase-order" class="label">
          <span class="label-text text-xs">Purchase Order</span>
        </label>
        <input
          type="text"
          id="edit-purchase-order"
          name={@edit_form[:purchase_order].name}
          value={@edit_form[:purchase_order].value}
          class="input input-sm input-bordered w-full"
          maxlength="256"
          placeholder="e.g. PO-2025-001"
        />
        <.field_error errors={@edit_form[:purchase_order].errors} />
      </div>

      <div class="flex gap-2 pt-2">
        <button type="submit" class="btn btn-sm btn-primary">Save</button>
        <button type="button" phx-click="cancel_edit" class="btn btn-sm btn-ghost">
          Cancel
        </button>
      </div>
    </.form>
    """
  end

  attr :edit_form, :map, required: true
  attr :readonly, :boolean, default: false
  attr :company, :map, required: true

  @spec seller_fields(map()) :: Phoenix.LiveView.Rendered.t()
  defp seller_fields(assigns) do
    ~H"""
    <div class="divider text-xs my-1">Seller</div>

    <div class="grid grid-cols-2 gap-3">
      <div class="form-control">
        <label for="edit-seller-name" class="label">
          <span class="label-text text-xs">Name</span>
        </label>
        <input
          :if={@readonly}
          type="text"
          id="edit-seller-name"
          value={@company.name}
          class="input input-sm input-bordered w-full bg-base-200 text-base-content/60"
          disabled
        />
        <input
          :if={!@readonly}
          type="text"
          id="edit-seller-name"
          name={@edit_form[:seller_name].name}
          value={@edit_form[:seller_name].value}
          class="input input-sm input-bordered w-full"
        />
        <.field_error :if={!@readonly} errors={@edit_form[:seller_name].errors} />
      </div>

      <div class="form-control">
        <label for="edit-seller-nip" class="label">
          <span class="label-text text-xs">NIP</span>
        </label>
        <input
          :if={@readonly}
          type="text"
          id="edit-seller-nip"
          value={@company.nip}
          class="input input-sm input-bordered w-full bg-base-200 text-base-content/60"
          disabled
        />
        <input
          :if={!@readonly}
          type="text"
          id="edit-seller-nip"
          name={@edit_form[:seller_nip].name}
          value={@edit_form[:seller_nip].value}
          class="input input-sm input-bordered w-full"
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
    <div class="divider text-xs my-1">Buyer</div>

    <div class="grid grid-cols-2 gap-3">
      <div class="form-control">
        <label for="edit-buyer-name" class="label">
          <span class="label-text text-xs">Name</span>
        </label>
        <input
          :if={@readonly}
          type="text"
          id="edit-buyer-name"
          value={@company.name}
          class="input input-sm input-bordered w-full bg-base-200 text-base-content/60"
          disabled
        />
        <input
          :if={!@readonly}
          type="text"
          id="edit-buyer-name"
          name={@edit_form[:buyer_name].name}
          value={@edit_form[:buyer_name].value}
          class="input input-sm input-bordered w-full"
        />
        <.field_error :if={!@readonly} errors={@edit_form[:buyer_name].errors} />
      </div>

      <div class="form-control">
        <label for="edit-buyer-nip" class="label">
          <span class="label-text text-xs">NIP</span>
        </label>
        <input
          :if={@readonly}
          type="text"
          id="edit-buyer-nip"
          value={@company.nip}
          class="input input-sm input-bordered w-full bg-base-200 text-base-content/60"
          disabled
        />
        <input
          :if={!@readonly}
          type="text"
          id="edit-buyer-nip"
          name={@edit_form[:buyer_nip].name}
          value={@edit_form[:buyer_nip].value}
          class="input input-sm input-bordered w-full"
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
    <div class="divider text-xs my-1">Amounts</div>

    <div class="grid grid-cols-3 gap-3">
      <div class="form-control">
        <label for="edit-net-amount" class="label">
          <span class="label-text text-xs">Netto</span>
        </label>
        <input
          type="text"
          inputmode="decimal"
          id="edit-net-amount"
          name={@edit_form[:net_amount].name}
          value={@edit_form[:net_amount].value}
          class="input input-sm input-bordered w-full font-mono"
        />
        <.field_error errors={@edit_form[:net_amount].errors} />
      </div>

      <div class="form-control">
        <label for="edit-gross-amount" class="label">
          <span class="label-text text-xs">Brutto</span>
        </label>
        <input
          type="text"
          inputmode="decimal"
          id="edit-gross-amount"
          name={@edit_form[:gross_amount].name}
          value={@edit_form[:gross_amount].value}
          class="input input-sm input-bordered w-full font-mono"
        />
        <.field_error errors={@edit_form[:gross_amount].errors} />
      </div>

      <div class="form-control">
        <label for="edit-currency" class="label">
          <span class="label-text text-xs">Currency</span>
        </label>
        <select
          id="edit-currency"
          name={@edit_form[:currency].name}
          class="select select-sm select-bordered w-full"
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

  attr :errors, :list, default: []

  @spec field_error(map()) :: Phoenix.LiveView.Rendered.t()
  defp field_error(assigns) do
    ~H"""
    <p :for={{msg, _opts} <- @errors} class="text-xs text-error mt-0.5">{msg}</p>
    """
  end
end
