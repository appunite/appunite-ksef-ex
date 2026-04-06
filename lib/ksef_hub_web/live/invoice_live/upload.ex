defmodule KsefHubWeb.InvoiceLive.Upload do
  @moduledoc """
  LiveView for uploading PDF expense invoices for extraction and storage.

  Accepts a single PDF file, sends it through the invoice extractor sidecar,
  creates the invoice record, and redirects to the show page for review.
  """
  use KsefHubWeb, :live_view

  require Logger

  alias KsefHub.Authorization
  alias KsefHub.Companies.Company
  alias KsefHub.Invoices

  import KsefHubWeb.UploadHelpers, only: [format_bytes: 1, upload_error_to_string: 1]

  @doc "Mounts the upload page with file upload configuration."
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Upload PDF Invoice", uploading: false, upload_refs: MapSet.new())
     |> allow_upload(:invoice_pdf,
       accept: ~w(.pdf),
       max_entries: 1,
       max_file_size: 10_000_000
     )}
  end

  @doc "Handles `validate` (no-op for live uploads) and `upload` (consumes file and starts extraction)."
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload", _params, socket) do
    if Authorization.can?(socket.assigns[:current_role], :create_invoice) do
      do_handle_upload(socket)
    else
      {:noreply,
       socket
       |> put_flash(:error, "You do not have permission to upload invoices.")
       |> redirect(to: ~p"/c/#{socket.assigns.current_company.id}/invoices")}
    end
  end

  @spec do_handle_upload(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_handle_upload(socket) do
    case consume_pdf(socket) do
      {:ok, {binary, filename}} ->
        start_upload_task(socket, binary, filename)

      {:error, :no_file} ->
        {:noreply, put_flash(socket, :error, "Please select a PDF file.")}

      {:error, {:read_failed, _reason}} ->
        {:noreply,
         put_flash(socket, :error, "Failed to read the uploaded file. Please try again.")}
    end
  end

  @doc "Handles async task results and process DOWN messages for upload processing."
  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({ref, {:ok, invoice, _meta}}, socket) when is_reference(ref) do
    if MapSet.member?(socket.assigns.upload_refs, ref) do
      Process.demonitor(ref, [:flush])

      {:noreply,
       socket
       |> update(:upload_refs, &MapSet.delete(&1, ref))
       |> put_flash(:info, "Invoice uploaded successfully.")
       |> redirect(to: ~p"/c/#{socket.assigns.current_company.id}/invoices/#{invoice.id}")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({ref, {:error, reason}}, socket) when is_reference(ref) do
    if MapSet.member?(socket.assigns.upload_refs, ref) do
      Process.demonitor(ref, [:flush])

      flash_msg = upload_error_message(reason)

      {:noreply,
       socket
       |> update(:upload_refs, &MapSet.delete(&1, ref))
       |> assign(uploading: false)
       |> put_flash(:error, flash_msg)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket) when is_reference(ref) do
    if MapSet.member?(socket.assigns.upload_refs, ref) do
      {:noreply,
       socket
       |> update(:upload_refs, &MapSet.delete(&1, ref))
       |> assign(uploading: false)
       |> put_flash(:error, "Upload processing crashed. Please try again.")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(msg, socket) do
    Logger.debug("InvoiceLive.Upload received unexpected message: #{inspect(msg)}")
    {:noreply, socket}
  end

  # --- Private ---

  @spec start_upload_task(Phoenix.LiveView.Socket.t(), binary(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp start_upload_task(socket, binary, filename) do
    company = socket.assigns.current_company
    user_id = socket.assigns.current_user.id

    task =
      Task.Supervisor.async_nolink(KsefHub.TaskSupervisor, fn ->
        do_upload(company, binary, filename, user_id)
      end)

    {:noreply,
     socket
     |> update(:upload_refs, &MapSet.put(&1, task.ref))
     |> assign(uploading: true)}
  end

  @spec consume_pdf(Phoenix.LiveView.Socket.t()) ::
          {:ok, {binary(), String.t()}} | {:error, :no_file | {:read_failed, atom()}}
  defp consume_pdf(socket) do
    results =
      consume_uploaded_entries(socket, :invoice_pdf, fn %{path: path}, entry ->
        case File.read(path) do
          {:ok, data} -> {:ok, {data, entry.client_name}}
          {:error, reason} -> {:ok, {:read_error, reason}}
        end
      end)

    case results do
      [{data, filename}] when is_binary(data) -> {:ok, {data, filename}}
      [{:read_error, reason}] -> {:error, {:read_failed, reason}}
      [] -> {:error, :no_file}
    end
  end

  @spec do_upload(Company.t(), binary(), String.t(), Ecto.UUID.t()) ::
          {:ok, Invoices.Invoice.t(), keyword()} | {:error, term()}
  defp do_upload(company, binary, filename, user_id) do
    Invoices.create_pdf_upload_invoice_with_meta(company, binary,
      type: :expense,
      filename: filename,
      created_by_id: user_id
    )
  end

  @spec upload_error_message(term()) :: String.t()
  defp upload_error_message(:buyer_nip_mismatch),
    do: "Invoice rejected: buyer NIP on the invoice doesn't match your company NIP."

  defp upload_error_message(:seller_nip_mismatch),
    do: "Invoice rejected: seller NIP on the invoice doesn't match your company NIP."

  defp upload_error_message(_reason),
    do: "Failed to process the PDF. Please try again."

  # --- Render ---

  @doc "Renders the PDF upload form with drag-and-drop zone and submit button."
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="breadcrumbs text-sm mb-2">
      <ul>
        <li><.link navigate={~p"/c/#{@current_company.id}/invoices"}>Invoices</.link></li>
        <li>Upload</li>
      </ul>
    </div>

    <.header>
      Upload PDF Invoice
      <:subtitle>Upload a PDF expense invoice for automatic data extraction</:subtitle>
    </.header>

    <div class="max-w-xl mt-6">
      <div :if={@uploading} class="border-2 border-dashed border-border rounded-lg p-12 text-center">
        <span class="loading loading-spinner loading-lg text-primary"></span>
        <p class="mt-3 font-medium">Processing your invoice...</p>
        <p class="text-sm text-muted-foreground mt-1">Extracting data from PDF</p>
      </div>

      <.form
        :if={!@uploading}
        for={%{}}
        phx-change="validate"
        phx-submit="upload"
        id="upload-form"
        class="space-y-6"
      >
        <div class="space-y-1">
          <label class="label"><span class="text-sm font-medium">PDF File</span></label>
          <div
            class="border-2 border-dashed border-border rounded-lg p-8 text-center"
            phx-drop-target={@uploads.invoice_pdf.ref}
          >
            <.live_file_input
              upload={@uploads.invoice_pdf}
              class="h-9 w-full rounded-md border border-input bg-background text-sm file:border-0 file:bg-muted file:text-muted-foreground file:text-sm file:font-medium file:mr-3 file:px-3 file:h-full"
            />
            <p :for={entry <- @uploads.invoice_pdf.entries} class="mt-2 text-sm">
              {entry.client_name}
              <span class="text-muted-foreground">({format_bytes(entry.client_size)})</span>
            </p>
            <p
              :for={err <- upload_errors(@uploads.invoice_pdf)}
              class="mt-1 text-shad-destructive text-sm"
            >
              {upload_error_to_string(err)}
            </p>
          </div>
          <p class="text-xs text-muted-foreground mt-1">Max file size: 10 MB</p>
        </div>

        <button
          type="submit"
          class="inline-flex items-center justify-center gap-2 h-9 px-4 text-sm font-medium rounded-md bg-shad-primary text-shad-primary-foreground hover:bg-shad-primary/90 transition-colors cursor-pointer"
          disabled={@uploads.invoice_pdf.entries == []}
        >
          Upload & Extract
        </button>
      </.form>
    </div>
    """
  end
end
