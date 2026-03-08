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
  def handle_info({ref, {:ok, invoice, meta}}, socket) when is_reference(ref) do
    if MapSet.member?(socket.assigns.upload_refs, ref) do
      Process.demonitor(ref, [:flush])

      {flash_kind, flash_msg} = upload_flash(meta, socket.assigns.current_company)

      {:noreply,
       socket
       |> update(:upload_refs, &MapSet.delete(&1, ref))
       |> put_flash(flash_kind, flash_msg)
       |> redirect(to: ~p"/c/#{socket.assigns.current_company.id}/invoices/#{invoice.id}")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({ref, {:error, _reason}}, socket) when is_reference(ref) do
    if MapSet.member?(socket.assigns.upload_refs, ref) do
      Process.demonitor(ref, [:flush])

      {:noreply,
       socket
       |> update(:upload_refs, &MapSet.delete(&1, ref))
       |> assign(uploading: false)
       |> put_flash(:error, "Failed to process the PDF. Please try again.")}
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

    task =
      Task.Supervisor.async_nolink(KsefHub.TaskSupervisor, fn ->
        do_upload(company, binary, filename)
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

  @spec do_upload(Company.t(), binary(), String.t()) ::
          {:ok, Invoices.Invoice.t(), keyword()} | {:error, term()}
  defp do_upload(company, binary, filename) do
    Invoices.create_pdf_upload_invoice_with_meta(company, binary,
      type: :expense,
      filename: filename
    )
  end

  @spec upload_flash(keyword(), Company.t()) :: {atom(), String.t()}
  defp upload_flash(meta, company) do
    extracted_buyer_nip = Keyword.get(meta, :extracted_buyer_nip)

    if extracted_buyer_nip && company.nip && extracted_buyer_nip != company.nip do
      {:warning, "Invoice uploaded but buyer NIP doesn't match your company. Please review."}
    else
      {:info, "Invoice uploaded successfully."}
    end
  end

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
      <div :if={@uploading} class="border-2 border-dashed border-base-300 rounded-lg p-12 text-center">
        <span class="loading loading-spinner loading-lg text-primary"></span>
        <p class="mt-3 font-medium">Processing your invoice...</p>
        <p class="text-sm text-base-content/60 mt-1">Extracting data from PDF</p>
      </div>

      <.form
        :if={!@uploading}
        for={%{}}
        phx-change="validate"
        phx-submit="upload"
        id="upload-form"
        class="space-y-6"
      >
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
              {upload_error_to_string(err)}
            </p>
          </div>
          <p class="text-xs text-base-content/50 mt-1">Max file size: 10 MB</p>
        </div>

        <button
          type="submit"
          class="btn btn-primary"
          disabled={@uploads.invoice_pdf.entries == []}
        >
          Upload & Extract
        </button>
      </.form>
    </div>
    """
  end
end
