defmodule KsefHubWeb.CertificateLive do
  @moduledoc """
  LiveView for managing PKCS12 certificates used for KSeF authentication.

  Certificates are stored at the user level (user_certificates table) since
  a KSeF person certificate is tied to the individual, not a company.
  The credential (company-level) stores only sync config (NIP, tokens).

  Supports two upload modes:
  - `:p12` — upload a single .p12/.pfx file (existing flow)
  - `:key_crt` — upload separate .key + .crt files (server-side conversion to PKCS12)
  """
  use KsefHubWeb, :live_view

  require Logger

  alias KsefHub.Credentials
  alias KsefHub.Credentials.Encryption
  alias KsefHub.KsefClient.AuthWorker

  @doc "Initializes the certificate management LiveView with upload configurations."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Certificates")
      |> assign(upload_mode: :key_crt)
      |> assign(form: to_form(%{"password" => ""}, as: :credential))
      |> allow_upload(:certificate,
        accept: ~w(application/x-pkcs12 .p12 .pfx),
        max_entries: 1,
        max_file_size: 1_000_000
      )
      |> allow_upload(:private_key,
        accept: ~w(.key .pem),
        max_entries: 1,
        max_file_size: 1_000_000
      )
      |> allow_upload(:certificate_crt,
        accept: ~w(.crt .pem .cer),
        max_entries: 1,
        max_file_size: 1_000_000
      )
      |> load_certificate_data()

    {:ok, socket}
  end

  @doc "Handles form validation, upload mode toggle, save, toggle_upload_form, and remove_certificate events."
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  @impl true
  def handle_event("validate", %{"credential" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :credential))}
  end

  @impl true
  def handle_event("toggle_upload_mode", %{"mode" => mode}, socket) do
    new_mode =
      case mode do
        "p12" -> :p12
        "key_crt" -> :key_crt
        _ -> socket.assigns.upload_mode
      end

    socket =
      socket
      |> assign(upload_mode: new_mode)
      |> assign(form: to_form(%{"password" => ""}, as: :credential))

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_upload_form", _params, socket) do
    {:noreply, assign(socket, show_upload_form: !socket.assigns.show_upload_form)}
  end

  @impl true
  def handle_event("save", %{"credential" => params}, socket) do
    case socket.assigns.upload_mode do
      :p12 -> save_p12(socket, params)
      :key_crt -> save_key_crt(socket, params)
    end
  end

  @impl true
  def handle_event("remove_certificate", _params, socket) do
    user = socket.assigns.current_user

    case Credentials.get_active_user_certificate(user.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "No active certificate found.")}

      cert ->
        case Credentials.deactivate_user_certificate(cert) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Certificate removed.")
             |> load_certificate_data()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to remove certificate.")}
        end
    end
  end

  # --- P12 upload flow ---

  @spec save_p12(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp save_p12(socket, params) do
    case consume_single_upload(socket, :certificate) do
      {:ok, cert_data} ->
        save_certificate(socket, cert_data, params["password"] || "")

      {:error, :no_file} ->
        {:noreply, put_flash(socket, :error, "Please upload a certificate file.")}

      {:error, {:file_read_failed, _reason}} ->
        {:noreply, put_flash(socket, :error, "Failed to read uploaded file.")}
    end
  end

  # --- Key + CRT upload flow ---

  @spec save_key_crt(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp save_key_crt(socket, params) do
    with {:ok, key_data} <- consume_single_upload(socket, :private_key),
         {:ok, crt_data} <- consume_single_upload(socket, :certificate_crt) do
      key_passphrase = non_empty_or_nil(params["key_passphrase"])

      case pkcs12_converter().convert(key_data, crt_data, key_passphrase) do
        {:ok, %{p12_data: p12_data, p12_password: p12_password}} ->
          save_certificate(socket, p12_data, p12_password)

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, format_error(reason))}
      end
    else
      {:error, :no_file} ->
        {:noreply,
         put_flash(socket, :error, "Please upload both private key and certificate files.")}

      {:error, {:file_read_failed, _reason}} ->
        {:noreply, put_flash(socket, :error, "Failed to read uploaded file.")}
    end
  end

  # --- Shared helpers ---

  @spec consume_single_upload(Phoenix.LiveView.Socket.t(), atom()) ::
          {:ok, binary()} | {:error, :no_file | {:file_read_failed, term()}}
  defp consume_single_upload(socket, upload_name) do
    case consume_uploaded_entries(socket, upload_name, &read_upload/2) do
      [data] when is_binary(data) -> {:ok, data}
      [{:error, reason}] -> {:error, {:file_read_failed, reason}}
      [] -> {:error, :no_file}
    end
  end

  @spec read_upload(map(), map()) :: {:ok, binary()} | {:ok, {:error, term()}}
  defp read_upload(%{path: path}, _entry) do
    case File.read(path) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:ok, {:error, reason}}
    end
  end

  @spec save_certificate(Phoenix.LiveView.Socket.t(), binary(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp save_certificate(%{assigns: %{current_company: nil}} = socket, _cert_data, _password) do
    {:noreply, socket |> put_flash(:error, "No company selected.") |> load_certificate_data()}
  end

  defp save_certificate(socket, cert_data, password) do
    user = socket.assigns.current_user
    company = socket.assigns.current_company
    cert_meta = extract_certificate_info(cert_data, password)

    with {:ok, encrypted_cert} <- Encryption.encrypt(cert_data),
         {:ok, encrypted_password} <- Encryption.encrypt(password) do
      attrs =
        %{
          certificate_data_encrypted: encrypted_cert,
          certificate_password_encrypted: encrypted_password
        }
        |> Map.merge(cert_meta)

      case Credentials.replace_active_user_certificate(user.id, attrs) do
        {:ok, _user_cert} ->
          ensure_credential_exists(company)
          enqueue_auth(company.id)

          {:noreply,
           socket
           |> put_flash(:info, "Certificate uploaded successfully.")
           |> assign(form: to_form(%{"password" => ""}, as: :credential))
           |> assign(show_upload_form: false)
           |> load_certificate_data()}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to save certificate.")}
      end
    else
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Encryption failed.")}
    end
  end

  @spec ensure_credential_exists(KsefHub.Companies.Company.t()) :: :ok
  defp ensure_credential_exists(company) do
    case Credentials.get_active_credential(company.id) do
      nil ->
        Credentials.replace_active_credential(company.id, %{})
        :ok

      _credential ->
        :ok
    end
  end

  @spec non_empty_or_nil(String.t() | nil) :: String.t() | nil
  defp non_empty_or_nil(nil), do: nil
  defp non_empty_or_nil(""), do: nil
  defp non_empty_or_nil(value), do: value

  @spec format_error(term()) :: String.t()
  defp format_error({:openssl_failed, 1}),
    do:
      "Invalid key passphrase or mismatched key/certificate. Please check your files and try again."

  defp format_error({:openssl_failed, code}),
    do: "Certificate processing failed (error #{code}). Please verify your files."

  defp format_error(:timeout), do: "Certificate processing timed out. Please try again."
  defp format_error(_reason), do: "Certificate processing failed. Please contact support."

  @spec extract_certificate_info(binary(), String.t()) :: map()
  defp extract_certificate_info(cert_data, password) do
    case certificate_info().extract(cert_data, password) do
      {:ok, info} ->
        %{certificate_subject: info.subject}
        |> put_if_present(:not_before, Map.get(info, :not_before))
        |> put_if_present(:not_after, Map.get(info, :expires_at))

      {:error, _reason} ->
        Logger.warning("Failed to extract certificate info")
        %{}
    end
  end

  @spec put_if_present(map(), atom(), term()) :: map()
  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  @spec pkcs12_converter() :: module()
  defp pkcs12_converter do
    Application.get_env(:ksef_hub, :pkcs12_converter, KsefHub.Credentials.Pkcs12Converter.Openssl)
  end

  @spec certificate_info() :: module()
  defp certificate_info do
    Application.get_env(:ksef_hub, :certificate_info, KsefHub.Credentials.CertificateInfo.Openssl)
  end

  @spec enqueue_auth(Ecto.UUID.t()) :: :ok
  defp enqueue_auth(company_id) do
    case %{company_id: company_id} |> AuthWorker.new() |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, _reason} ->
        Logger.error("Failed to enqueue auth job for company #{company_id}")
        :ok
    end
  end

  @spec load_certificate_data(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_certificate_data(%{assigns: %{current_company: nil}} = socket) do
    socket
    |> assign(user_certificate: nil, active_credential: nil, show_upload_form: true)
  end

  defp load_certificate_data(socket) do
    user = socket.assigns.current_user
    company = socket.assigns.current_company
    user_cert = Credentials.get_active_user_certificate(user.id)
    credential = Credentials.get_active_credential(company.id)
    show_form = socket.assigns[:show_upload_form] || is_nil(user_cert)

    socket
    |> assign(
      user_certificate: user_cert,
      active_credential: credential,
      show_upload_form: show_form
    )
  end

  @doc "Renders the certificate management view."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Certificate
      <:subtitle>Your personal KSeF certificate — used for all your companies</:subtitle>
    </.header>

    <!-- Current Certificate -->
    <div
      :if={@user_certificate}
      id="current-certificate"
      class="card bg-base-100 border border-base-300 mt-6"
    >
      <div class="p-5">
        <h2 class="text-base font-semibold">Your Certificate</h2>
        <.list>
          <:item :if={@user_certificate.certificate_subject} title="Issued To">
            {@user_certificate.certificate_subject}
          </:item>
          <:item :if={@user_certificate.not_before} title="Valid From">
            {Calendar.strftime(@user_certificate.not_before, "%Y-%m-%d")}
          </:item>
          <:item :if={@user_certificate.not_after} title="Valid Until">
            <span class={cert_expiry_class(@user_certificate.not_after)}>
              {Calendar.strftime(@user_certificate.not_after, "%Y-%m-%d")}
            </span>
          </:item>
          <:item :if={@user_certificate.fingerprint} title="Fingerprint">
            <span class="font-mono text-xs">{@user_certificate.fingerprint}</span>
          </:item>
          <:item title="Uploaded">
            {Calendar.strftime(@user_certificate.inserted_at, "%Y-%m-%d %H:%M UTC")}
          </:item>
        </.list>
        <div class="flex gap-2 mt-4">
          <button
            type="button"
            phx-click="toggle_upload_form"
            class="btn btn-sm btn-outline"
          >
            <.icon name="hero-arrow-path" class="size-4" />
            {if @show_upload_form, do: "Cancel", else: "Replace Certificate"}
          </button>
          <button
            type="button"
            phx-click="remove_certificate"
            data-confirm="Are you sure you want to remove this certificate? This will disable KSeF sync."
            class="btn btn-sm btn-ghost text-error"
          >
            <.icon name="hero-trash" class="size-4" /> Remove
          </button>
        </div>
      </div>
    </div>

    <!-- Empty State -->
    <div
      :if={!@user_certificate}
      id="no-certificate"
      class="card bg-base-100 border border-base-300 mt-6"
    >
      <div class="p-8 text-center">
        <.icon name="hero-shield-exclamation" class="size-12 text-base-content/30 mx-auto" />
        <h2 class="text-base font-semibold mt-3">No Certificate Configured</h2>
        <p class="text-sm text-base-content/60 mt-1">
          Upload a certificate to enable KSeF synchronization.
        </p>
      </div>
    </div>

    <!-- Upload Form -->
    <div :if={@show_upload_form} id="upload-form" class="card bg-base-100 border border-base-300 mt-6">
      <div class="p-5">
        <h2 class="text-base font-semibold">Upload Certificate</h2>
        
    <!-- Mode Toggle -->
        <div class="flex gap-2 mt-3 mb-4" id="upload-mode-toggle">
          <button
            type="button"
            phx-click="toggle_upload_mode"
            phx-value-mode="key_crt"
            class={"btn btn-sm #{if @upload_mode == :key_crt, do: "btn-primary", else: "btn-ghost"}"}
          >
            .key + .crt
          </button>
          <button
            type="button"
            phx-click="toggle_upload_mode"
            phx-value-mode="p12"
            class={"btn btn-sm #{if @upload_mode == :p12, do: "btn-primary", else: "btn-ghost"}"}
          >
            .p12 / .pfx
          </button>
        </div>

        <.form
          for={@form}
          phx-submit="save"
          phx-change="validate"
          class="space-y-4"
          id="certificate-upload"
        >
          <!-- P12 upload -->
          <div :if={@upload_mode == :p12} class="form-control">
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
              <p
                :for={err <- upload_errors(@uploads.certificate)}
                class="mt-1 text-error text-sm"
              >
                {error_to_string(err)}
              </p>
            </div>
          </div>
          
    <!-- Key + CRT upload -->
          <div :if={@upload_mode == :key_crt} class="space-y-4">
            <div class="form-control">
              <label class="label">
                <span class="label-text">Private Key File (.key / .pem)</span>
              </label>
              <div
                class="border-2 border-dashed border-base-300 rounded-lg p-6 text-center"
                phx-drop-target={@uploads.private_key.ref}
              >
                <.live_file_input
                  upload={@uploads.private_key}
                  class="file-input file-input-bordered file-input-sm"
                />
                <p :for={entry <- @uploads.private_key.entries} class="mt-2 text-sm">
                  {entry.client_name}
                  <span class="text-base-content/60">({format_bytes(entry.client_size)})</span>
                </p>
                <p
                  :for={err <- upload_errors(@uploads.private_key)}
                  class="mt-1 text-error text-sm"
                >
                  {error_to_string(err)}
                </p>
              </div>
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">Certificate File (.crt / .pem / .cer)</span>
              </label>
              <div
                class="border-2 border-dashed border-base-300 rounded-lg p-6 text-center"
                phx-drop-target={@uploads.certificate_crt.ref}
              >
                <.live_file_input
                  upload={@uploads.certificate_crt}
                  class="file-input file-input-bordered file-input-sm"
                />
                <p :for={entry <- @uploads.certificate_crt.entries} class="mt-2 text-sm">
                  {entry.client_name}
                  <span class="text-base-content/60">({format_bytes(entry.client_size)})</span>
                </p>
                <p
                  :for={err <- upload_errors(@uploads.certificate_crt)}
                  class="mt-1 text-error text-sm"
                >
                  {error_to_string(err)}
                </p>
              </div>
            </div>

            <.input
              field={@form[:key_passphrase]}
              type="password"
              label="Key Passphrase (leave empty if unencrypted)"
            />
          </div>
          
    <!-- Password field for P12 mode -->
          <div :if={@upload_mode == :p12}>
            <.input
              field={@form[:password]}
              type="password"
              label="Certificate Password"
              required
            />
          </div>

          <button type="submit" class="btn btn-primary">
            <.icon name="hero-arrow-up-tray" class="size-4" /> Upload Certificate
          </button>
        </.form>
      </div>
    </div>
    """
  end

  @spec cert_expiry_class(Date.t() | nil) :: String.t()
  defp cert_expiry_class(nil), do: ""

  defp cert_expiry_class(date) do
    days_left = Date.diff(date, Date.utc_today())

    cond do
      days_left < 0 -> "text-error font-bold"
      days_left < 30 -> "text-warning font-semibold"
      true -> ""
    end
  end

  @spec format_bytes(non_neg_integer()) :: String.t()
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"

  @spec error_to_string(atom()) :: String.t()
  defp error_to_string(:too_large), do: "File is too large (max 1 MB)."
  defp error_to_string(:not_accepted), do: "Invalid file type."
  defp error_to_string(:too_many_files), do: "Only one file allowed."
  defp error_to_string(err), do: "Upload error: #{inspect(err)}"
end
