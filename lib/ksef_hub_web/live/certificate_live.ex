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

  import KsefHubWeb.CertificateComponents, only: [cert_expiry_alert: 1]
  import KsefHubWeb.InvoiceComponents, only: [format_date: 1]
  import KsefHubWeb.SettingsComponents, only: [settings_layout: 1]

  require Logger

  alias KsefHub.Companies
  alias KsefHub.Credentials
  alias KsefHub.Credentials.{Encryption, UserCertificate}
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
          ensure_credentials_and_auth_for_user(user)

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

  @spec ensure_credentials_and_auth_for_user(KsefHub.Accounts.User.t()) :: :ok
  defp ensure_credentials_and_auth_for_user(user) do
    user.id
    |> Companies.list_owned_companies_for_user()
    |> Enum.each(fn company ->
      case Credentials.ensure_credential_for_company(company.id) do
        {:ok, _credential} ->
          AuthWorker.enqueue(company.id)

        {:error, _changeset} ->
          Logger.warning("Failed to create credential for company #{company.id}")
      end
    end)
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

  @spec load_certificate_data(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_certificate_data(%{assigns: %{current_company: nil}} = socket) do
    socket
    |> assign(
      user_certificate: nil,
      certificate_history: [],
      active_credential: nil,
      show_upload_form: true,
      cert_expiry_status: :no_certificate
    )
  end

  defp load_certificate_data(socket) do
    user = socket.assigns.current_user
    company = socket.assigns.current_company
    user_cert = Credentials.get_active_user_certificate(user.id)
    credential = Credentials.get_active_credential(company.id)
    show_form = socket.assigns[:show_upload_form] || is_nil(user_cert)
    cert_expiry = Credentials.certificate_expiry_status(company.id)
    history = Credentials.list_inactive_user_certificates(user.id)

    socket
    |> assign(
      user_certificate: user_cert,
      certificate_history: history,
      active_credential: credential,
      show_upload_form: show_form,
      cert_expiry_status: cert_expiry
    )
  end

  @doc "Renders the certificate management view."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  @impl true
  def render(assigns) do
    ~H"""
    <.settings_layout
      current_path={@current_path}
      current_company={@current_company}
      current_role={@current_role}
    >
      <.header>
        Certificate
        <:subtitle>Your personal KSeF certificate — used for all your companies</:subtitle>
      </.header>

      <.cert_expiry_alert status={@cert_expiry_status} class="mt-6" />
      
    <!-- Current Certificate -->
      <.card :if={@user_certificate} id="current-certificate" class="mt-6">
        <div class="flex items-center justify-between mb-4">
          <h2 id="cert-heading" class="text-base font-semibold">Active certificate</h2>
          <.badge variant={cert_status_variant(@user_certificate.not_after)}>
            {cert_status_label(@user_certificate.not_after)}
          </.badge>
        </div>
        <.list>
          <:item title="Subject">
            <span id="cert-subject" class="font-mono text-xs">{cert_display_subject(@user_certificate)}</span>
          </:item>
          <:item :if={@user_certificate.fingerprint} title="Serial">
            <span class="font-mono text-xs">{@user_certificate.fingerprint}</span>
          </:item>
          <:item title="Issued">
            <span class="font-mono text-xs">{format_date(@user_certificate.not_before)}</span>
          </:item>
          <:item title="Expires">
            <span class={["font-mono text-xs", cert_expiry_class(@user_certificate.not_after)]}>
              {format_expiry(@user_certificate.not_after)}
            </span>
          </:item>
        </.list>
        <p
          :if={is_nil(@user_certificate.certificate_subject)}
          class="text-xs text-muted-foreground mt-2"
        >
          Certificate details incomplete — replace to refresh metadata.
        </p>
        <div class="flex gap-2 mt-4">
          <.button variant="outline" type="button" phx-click="toggle_upload_form">
            <.icon name="hero-arrow-path" class="size-4" />
            {if @show_upload_form, do: "Cancel", else: "Replace Certificate"}
          </.button>
          <.button
            variant="ghost"
            class="text-shad-destructive"
            type="button"
            phx-click="remove_certificate"
            data-confirm="Are you sure you want to remove this certificate? This will disable KSeF sync."
          >
            <.icon name="hero-trash" class="size-4" /> Remove
          </.button>
        </div>
      </.card>
      
    <!-- Empty State -->
      <.card :if={!@user_certificate} id="no-certificate" class="mt-6" padding="p-8 text-center">
        <.icon name="hero-shield-exclamation" class="size-12 text-muted-foreground mx-auto" />
        <h2 class="text-base font-semibold mt-3">No Certificate Configured</h2>
        <p class="text-sm text-muted-foreground mt-1">
          Upload a certificate to enable KSeF synchronization.
        </p>
      </.card>
      
    <!-- Upload Form -->
      <.card :if={@show_upload_form} id="upload-form" class="mt-6">
        <h2 class="text-base font-semibold">Upload Certificate</h2>
        
    <!-- Mode Toggle -->
        <div class="flex gap-2 mt-3 mb-4" id="upload-mode-toggle">
          <.button
            type="button"
            variant={if @upload_mode == :key_crt, do: "primary", else: "ghost"}
            phx-click="toggle_upload_mode"
            phx-value-mode="key_crt"
          >
            .key + .crt
          </.button>
          <.button
            type="button"
            variant={if @upload_mode == :p12, do: "primary", else: "ghost"}
            phx-click="toggle_upload_mode"
            phx-value-mode="p12"
          >
            .p12 / .pfx
          </.button>
        </div>

        <.form
          for={@form}
          phx-submit="save"
          phx-change="validate"
          class="space-y-4"
          id="certificate-upload"
        >
          <!-- P12 upload -->
          <div :if={@upload_mode == :p12}>
            <.file_upload_dropzone
              upload={@uploads.certificate}
              label="Certificate File (.p12 / .pfx)"
            >
              <p :for={entry <- @uploads.certificate.entries} class="mt-2 text-sm">
                {entry.client_name}
                <span class="text-muted-foreground">({format_bytes(entry.client_size)})</span>
              </p>
              <p
                :for={err <- upload_errors(@uploads.certificate)}
                class="mt-1 text-shad-destructive text-sm"
              >
                {error_to_string(err)}
              </p>
            </.file_upload_dropzone>
          </div>
          
    <!-- Key + CRT upload -->
          <div :if={@upload_mode == :key_crt} class="space-y-4">
            <.file_upload_dropzone
              upload={@uploads.private_key}
              label="Private Key File (.key / .pem)"
            >
              <p :for={entry <- @uploads.private_key.entries} class="mt-2 text-sm">
                {entry.client_name}
                <span class="text-muted-foreground">({format_bytes(entry.client_size)})</span>
              </p>
              <p
                :for={err <- upload_errors(@uploads.private_key)}
                class="mt-1 text-shad-destructive text-sm"
              >
                {error_to_string(err)}
              </p>
            </.file_upload_dropzone>

            <.file_upload_dropzone
              upload={@uploads.certificate_crt}
              label="Certificate File (.crt / .pem / .cer)"
            >
              <p :for={entry <- @uploads.certificate_crt.entries} class="mt-2 text-sm">
                {entry.client_name}
                <span class="text-muted-foreground">({format_bytes(entry.client_size)})</span>
              </p>
              <p
                :for={err <- upload_errors(@uploads.certificate_crt)}
                class="mt-1 text-shad-destructive text-sm"
              >
                {error_to_string(err)}
              </p>
            </.file_upload_dropzone>

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

          <.button type="submit">
            <.icon name="hero-arrow-up-tray" class="size-4" /> Upload Certificate
          </.button>
        </.form>
      </.card>

      <.card :if={@certificate_history != []} class="mt-6">
        <h2 class="text-base font-semibold">Certificate history</h2>
        <p class="text-sm text-muted-foreground mt-0.5 mb-4">
          Superseded and revoked certs stay in the audit log.
        </p>
        <div class="space-y-2">
          <div
            :for={cert <- @certificate_history}
            class="flex items-center justify-between px-4 py-3 rounded-lg border border-border"
          >
            <div>
              <div class="font-mono text-sm">{cert.fingerprint || cert.certificate_subject || "—"}</div>
              <div class="text-xs text-muted-foreground mt-0.5">
                replaced on {Calendar.strftime(cert.updated_at, "%Y-%m-%d")}
              </div>
            </div>
            <.badge variant="muted">superseded</.badge>
          </div>
        </div>
      </.card>
    </.settings_layout>
    """
  end

  @spec cert_display_subject(UserCertificate.t()) :: String.t()
  defp cert_display_subject(%{certificate_subject: nil}), do: "-"
  defp cert_display_subject(%{certificate_subject: subject}), do: subject

  @spec cert_expiry_class(Date.t() | nil) :: String.t()
  defp cert_expiry_class(nil), do: ""

  defp cert_expiry_class(date) do
    days_left = Date.diff(date, Date.utc_today())

    cond do
      days_left < 7 -> "text-shad-destructive font-bold"
      days_left < 30 -> "text-warning font-semibold"
      true -> ""
    end
  end

  @spec cert_status_variant(Date.t() | nil) :: String.t()
  defp cert_status_variant(nil), do: "muted"

  defp cert_status_variant(date) do
    days_left = Date.diff(date, Date.utc_today())

    cond do
      days_left <= 0 -> "error"
      days_left <= 30 -> "warning"
      true -> "success"
    end
  end

  @spec cert_status_label(Date.t() | nil) :: String.t()
  defp cert_status_label(nil), do: "no certificate"

  defp cert_status_label(date) do
    days_left = Date.diff(date, Date.utc_today())

    cond do
      days_left <= 0 -> "expired"
      days_left <= 30 -> "expiring soon"
      true -> "✓ valid"
    end
  end

  @spec format_expiry(Date.t() | nil) :: String.t()
  defp format_expiry(nil), do: "-"

  defp format_expiry(date) do
    days_left = Date.diff(date, Date.utc_today())
    date_str = format_date(date)

    cond do
      days_left <= 0 -> "#{date_str} · #{abs(days_left)} days ago"
      days_left == 1 -> "#{date_str} · 1 day left"
      true -> "#{date_str} · #{days_left} days left"
    end
  end

  @spec format_bytes(non_neg_integer()) :: String.t()
  defp format_bytes(bytes), do: KsefHubWeb.UploadHelpers.format_bytes(bytes)

  @spec error_to_string(atom()) :: String.t()
  defp error_to_string(err), do: KsefHubWeb.UploadHelpers.upload_error_to_string(err)
end
