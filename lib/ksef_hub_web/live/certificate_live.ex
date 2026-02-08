defmodule KsefHubWeb.CertificateLive do
  @moduledoc """
  LiveView for managing PKCS12 certificates used for KSeF authentication.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Credentials
  alias KsefHub.Credentials.Encryption

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Certificates")
      |> assign(form: to_form(%{"password" => ""}, as: :credential))
      |> allow_upload(:certificate,
        accept: ~w(application/x-pkcs12 .p12 .pfx),
        max_entries: 1,
        max_file_size: 1_000_000
      )
      |> load_credentials()

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"credential" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :credential))}
  end

  @impl true
  def handle_event("save", %{"credential" => params}, socket) do
    case uploaded_cert_data(socket) do
      {:ok, cert_data} ->
        save_credential(socket, params, cert_data)

      {:error, :no_file} ->
        {:noreply, put_flash(socket, :error, "Please upload a certificate file.")}

      {:error, {:file_read_failed, _reason}} ->
        {:noreply, put_flash(socket, :error, "Failed to read uploaded file.")}
    end
  end

  @impl true
  def handle_event("deactivate", %{"id" => id}, socket) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %{} = credential <- Credentials.get_credential(uuid) do
      case Credentials.deactivate_credential(credential) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Certificate deactivated.")
           |> load_credentials()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to deactivate certificate.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Certificate not found.")}
    end
  end

  @spec uploaded_cert_data(Phoenix.LiveView.Socket.t()) ::
          {:ok, binary()} | {:error, :no_file | {:file_read_failed, term()}}
  defp uploaded_cert_data(socket) do
    case consume_uploaded_entries(socket, :certificate, &read_upload/2) do
      [{:ok, data}] -> {:ok, data}
      [{:ok, {:error, reason}}] -> {:error, {:file_read_failed, reason}}
      [] -> {:error, :no_file}
    end
  end

  @spec read_upload(map(), map()) :: {:ok, binary() | {:error, term()}}
  defp read_upload(%{path: path}, _entry) do
    case File.read(path) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:ok, {:error, reason}}
    end
  end

  @spec save_credential(Phoenix.LiveView.Socket.t(), map(), binary()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp save_credential(%{assigns: %{current_company: nil}} = socket, _params, _cert_data) do
    {:noreply, socket |> put_flash(:error, "No company selected.") |> load_credentials()}
  end

  defp save_credential(socket, params, cert_data) do
    company = socket.assigns.current_company

    with {:ok, encrypted_cert} <- Encryption.encrypt(cert_data),
         {:ok, encrypted_password} <- Encryption.encrypt(params["password"] || "") do
      attrs = %{
        certificate_data_encrypted: encrypted_cert,
        certificate_password_encrypted: encrypted_password,
        is_active: true
      }

      case Credentials.replace_active_credential(company.id, attrs) do
        {:ok, _credential} ->
          {:noreply,
           socket
           |> put_flash(:info, "Certificate uploaded successfully.")
           |> assign(form: to_form(%{"password" => ""}, as: :credential))
           |> load_credentials()}

        {:error, changeset} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to save certificate.")
           |> assign(form: to_form(changeset, as: :credential))}
      end
    else
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Encryption failed.")}
    end
  end

  @spec load_credentials(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_credentials(%{assigns: %{current_company: nil}} = socket) do
    socket
    |> assign(has_credentials: false, active_credential: nil)
    |> stream(:credentials, [], reset: true)
  end

  defp load_credentials(%{assigns: %{current_company: company}} = socket) do
    credentials = Credentials.list_credentials(company.id)
    active = Credentials.get_active_credential(company.id)

    socket
    |> assign(has_credentials: credentials != [], active_credential: active)
    |> stream(:credentials, credentials, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Certificates
      <:subtitle>Manage KSeF PKCS12 certificates for authentication</:subtitle>
    </.header>

    <!-- Active Certificate -->
    <div
      :if={@active_credential}
      id="active-certificate"
      class="card bg-base-100 border border-base-300 mt-6"
    >
      <div class="p-5">
        <div class="flex items-center justify-between">
          <h2 class="text-base font-semibold">Active Certificate</h2>
          <.active_badge active={true} />
        </div>
        <.list>
          <:item title="NIP">{@active_credential.nip}</:item>
          <:item :if={@active_credential.certificate_subject} title="Subject">
            {@active_credential.certificate_subject}
          </:item>
          <:item :if={@active_credential.certificate_expires_at} title="Expires">
            {Calendar.strftime(@active_credential.certificate_expires_at, "%Y-%m-%d")}
          </:item>
          <:item :if={@active_credential.last_sync_at} title="Last Sync">
            {Calendar.strftime(@active_credential.last_sync_at, "%Y-%m-%d %H:%M UTC")}
          </:item>
        </.list>
      </div>
    </div>

    <!-- Upload Form -->
    <div class="card bg-base-100 border border-base-300 mt-6">
      <div class="p-5">
        <h2 class="text-base font-semibold">Upload New Certificate</h2>
        <form phx-submit="save" phx-change="validate" class="space-y-4 mt-2">
          <div class="form-control">
            <label class="label">
              <span class="label-text">Certificate File (.p12 / .pfx)</span>
            </label>
            <div
              class="border-2 border-dashed border-base-300 rounded-lg p-6 text-center"
              phx-drop-target={@uploads.certificate.ref}
            >
              <.live_file_input
                upload={@uploads.certificate}
                class="file-input file-input-bordered file-input-sm"
              />
              <p :for={entry <- @uploads.certificate.entries} class="mt-2 text-sm">
                {entry.client_name}
                <span class="text-base-content/60">({format_bytes(entry.client_size)})</span>
              </p>
              <p :for={err <- upload_errors(@uploads.certificate)} class="mt-1 text-error text-sm">
                {error_to_string(err)}
              </p>
            </div>
          </div>

          <.input field={@form[:password]} type="password" label="Certificate Password" required />

          <button type="submit" class="btn btn-primary">
            <.icon name="hero-arrow-up-tray" class="size-4" /> Upload Certificate
          </button>
        </form>
      </div>
    </div>

    <!-- All Certificates -->
    <div :if={@has_credentials} class="mt-6">
      <h2 class="text-lg font-semibold mb-3">All Certificates</h2>
      <div class="overflow-x-auto">
        <.table
          id="credentials"
          rows={@streams.credentials}
          row_id={fn {id, _} -> id end}
          row_item={fn {_id, item} -> item end}
        >
          <:col :let={cred} label="NIP">{cred.nip}</:col>
          <:col :let={cred} label="Subject">{cred.certificate_subject || "-"}</:col>
          <:col :let={cred} label="Expires">
            {if cred.certificate_expires_at,
              do: Calendar.strftime(cred.certificate_expires_at, "%Y-%m-%d"),
              else: "-"}
          </:col>
          <:col :let={cred} label="Status">
            <.active_badge active={cred.is_active} />
          </:col>
          <:action :let={cred}>
            <button
              :if={cred.is_active}
              phx-click="deactivate"
              phx-value-id={cred.id}
              data-confirm="Are you sure you want to deactivate this certificate?"
              class="btn btn-ghost btn-xs text-error"
            >
              Deactivate
            </button>
          </:action>
        </.table>
      </div>
    </div>
    """
  end

  @spec active_badge(map()) :: Phoenix.LiveView.Rendered.t()
  defp active_badge(%{active: true} = assigns) do
    ~H"""
    <span class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border bg-success/10 text-success border-success/20">
      Active
    </span>
    """
  end

  defp active_badge(%{active: active} = assigns) when active in [false, nil] do
    ~H"""
    <span class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border bg-base-200 text-base-content/60 border-base-300">
      Inactive
    </span>
    """
  end

  @spec format_bytes(non_neg_integer()) :: String.t()
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"

  @spec error_to_string(atom()) :: String.t()
  defp error_to_string(:too_large), do: "File is too large (max 1 MB)."
  defp error_to_string(:not_accepted), do: "Invalid file type. Please upload a .p12 or .pfx file."
  defp error_to_string(:too_many_files), do: "Only one file allowed."
  defp error_to_string(err), do: "Upload error: #{inspect(err)}"
end
