defmodule KsefHubWeb.InvoiceLive.Upload do
  @moduledoc """
  LiveView for uploading PDF invoices for extraction and storage.

  Accepts a single PDF file, sends it through the invoice extractor sidecar,
  creates the invoice record, and redirects to the show page for review.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Invoices

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Upload PDF Invoice", type: "expense", uploading: false)
     |> allow_upload(:invoice_pdf,
       accept: ~w(.pdf),
       max_entries: 1,
       max_file_size: 10_000_000
     )}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("set_type", %{"type" => type}, socket) when type in ~w(income expense) do
    {:noreply, assign(socket, :type, type)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload", _params, socket) do
    company = socket.assigns[:current_company]

    if is_nil(company) do
      {:noreply, put_flash(socket, :error, "No company selected.")}
    else
      case consume_pdf(socket) do
        {:ok, {binary, filename}} ->
          type = String.to_existing_atom(socket.assigns.type)
          task = Task.async(fn -> do_upload(company, binary, type, filename) end)

          {:noreply, assign(socket, uploading: true, upload_ref: task.ref)}

        {:error, :no_file} ->
          {:noreply, put_flash(socket, :error, "Please select a PDF file.")}
      end
    end
  end

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({ref, {:ok, invoice}}, %{assigns: %{upload_ref: ref}} = socket) do
    Process.demonitor(ref, [:flush])

    {:noreply,
     socket
     |> put_flash(:info, "Invoice uploaded successfully.")
     |> redirect(to: ~p"/invoices/#{invoice.id}")}
  end

  def handle_info({ref, {:error, _reason}}, %{assigns: %{upload_ref: ref}} = socket) do
    Process.demonitor(ref, [:flush])

    {:noreply,
     socket
     |> assign(uploading: false, upload_ref: nil)
     |> put_flash(:error, "Failed to process the PDF. Please try again.")}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{upload_ref: ref}} = socket) do
    {:noreply,
     socket
     |> assign(uploading: false, upload_ref: nil)
     |> put_flash(:error, "Upload processing crashed. Please try again.")}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Private ---

  @spec consume_pdf(Phoenix.LiveView.Socket.t()) ::
          {:ok, {binary(), String.t()}} | {:error, :no_file}
  defp consume_pdf(socket) do
    results =
      consume_uploaded_entries(socket, :invoice_pdf, fn %{path: path}, entry ->
        case File.read(path) do
          {:ok, data} -> {:ok, {data, entry.client_name}}
          {:error, reason} -> {:ok, {:error, reason}}
        end
      end)

    case results do
      [{data, filename}] when is_binary(data) -> {:ok, {data, filename}}
      [{:error, _reason}] -> {:error, :no_file}
      [] -> {:error, :no_file}
    end
  end

  @spec do_upload(map(), binary(), atom(), String.t()) ::
          {:ok, Invoices.Invoice.t()} | {:error, term()}
  defp do_upload(company, binary, type, filename) do
    Invoices.create_pdf_upload_invoice(company, binary, type: type, filename: filename)
  end

  # --- Render ---

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.header>
      Upload PDF Invoice
      <:subtitle>Upload a PDF invoice for automatic data extraction</:subtitle>
    </.header>

    <div class="max-w-xl mt-6">
      <.form for={%{}} phx-change="validate" phx-submit="upload" id="upload-form" class="space-y-6">
        <div class="form-control">
          <label class="label"><span class="label-text">Invoice Type</span></label>
          <div class="flex gap-4">
            <label class="flex items-center gap-2 cursor-pointer">
              <input
                type="radio"
                name="type"
                value="expense"
                checked={@type == "expense"}
                phx-click="set_type"
                phx-value-type="expense"
                class="radio radio-sm"
              />
              <span class="label-text">Expense</span>
            </label>
            <label class="flex items-center gap-2 cursor-pointer">
              <input
                type="radio"
                name="type"
                value="income"
                checked={@type == "income"}
                phx-click="set_type"
                phx-value-type="income"
                class="radio radio-sm"
              />
              <span class="label-text">Income</span>
            </label>
          </div>
        </div>

        <div class="form-control">
          <label class="label"><span class="label-text">PDF File</span></label>
          <div
            class="border-2 border-dashed border-base-300 rounded-lg p-8 text-center"
            phx-drop-target={@uploads.invoice_pdf.ref}
          >
            <.live_file_input
              upload={@uploads.invoice_pdf}
              class="file-input file-input-bordered file-input-sm"
            />
            <p :for={entry <- @uploads.invoice_pdf.entries} class="mt-2 text-sm">
              {entry.client_name}
              <span class="text-base-content/60">({format_bytes(entry.client_size)})</span>
            </p>
            <p
              :for={err <- upload_errors(@uploads.invoice_pdf)}
              class="mt-1 text-error text-sm"
            >
              {error_to_string(err)}
            </p>
          </div>
          <p class="text-xs text-base-content/50 mt-1">Max file size: 10 MB</p>
        </div>

        <button
          type="submit"
          class="btn btn-primary"
          disabled={@uploading || @uploads.invoice_pdf.entries == []}
        >
          <span :if={@uploading} class="loading loading-spinner loading-sm"></span>
          {if @uploading, do: "Processing...", else: "Upload & Extract"}
        </button>
      </.form>

      <div class="mt-6">
        <.link navigate={~p"/invoices"} class="btn btn-ghost btn-sm">
          <.icon name="hero-arrow-left" class="size-4" /> Back to invoices
        </.link>
      </div>
    </div>
    """
  end

  @spec format_bytes(non_neg_integer()) :: String.t()
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"

  @spec error_to_string(atom()) :: String.t()
  defp error_to_string(:too_large), do: "File is too large (max 10 MB)."
  defp error_to_string(:not_accepted), do: "Only PDF files are accepted."
  defp error_to_string(:too_many_files), do: "Only one file allowed."
  defp error_to_string(err), do: "Upload error: #{inspect(err)}"
end
