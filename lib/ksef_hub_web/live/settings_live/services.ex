defmodule KsefHubWeb.SettingsLive.Services do
  @moduledoc """
  Settings page for configuring the invoice classifier sidecar per company.

  By default, the classifier uses global env-var configuration. When enabled,
  the company's custom URL, token, and thresholds override the defaults.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.ServiceConfig
  alias KsefHub.ServiceConfig.ClassifierConfig

  import KsefHubWeb.SettingsComponents, only: [settings_layout: 1]

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    company_id = socket.assigns.current_company.id
    config = ServiceConfig.get_or_create_classifier_config(company_id)
    env = ServiceConfig.env_defaults()

    socket =
      socket
      |> assign(
        page_title: "Services",
        config: config,
        env_defaults: env,
        form: build_form(config, env),
        health: nil,
        confirm_save: false,
        pending_params: nil,
        docs_expanded: false
      )

    if connected?(socket), do: check_health_async(config, env)

    {:ok, socket}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.settings_layout
      current_path={@current_path}
      current_company={@current_company}
      current_role={@current_role}
    >
      <.header>
        Services
        <:subtitle>Configure sidecar service connections for this company</:subtitle>
      </.header>

      <div class="mt-6">
        <div class="rounded-xl border border-border bg-card p-6">
          <div class="mb-4">
            <h3 class="text-base font-semibold">Invoice Classifier</h3>
            <p class="text-sm text-muted-foreground mt-1">
              ML-based category and tag classification for expense invoices.
            </p>
          </div>

          <.simple_form for={@form} phx-change="validate" phx-submit="save">
            <div class="space-y-4">
              <.input
                field={@form[:enabled]}
                type="checkbox"
                label="Override environment variables with custom settings"
              />

              <p :if={!@form[:enabled].value} class="text-sm text-muted-foreground -mt-2">
                Using environment variable defaults. Enable to configure custom values for this company.
              </p>

              <fieldset
                disabled={!@form[:enabled].value}
                class={["space-y-4", !@form[:enabled].value && "opacity-50"]}
              >
                <.input
                  field={@form[:url]}
                  type="url"
                  label="URL"
                  placeholder={@env_defaults.url || "http://localhost:3003"}
                />

                <.input
                  field={@form[:api_token]}
                  type="password"
                  label="API Token"
                  placeholder={
                    cond do
                      @config.api_token_encrypted -> "configured (leave blank to keep)"
                      @env_defaults.api_token_configured -> "using env var (leave blank to keep)"
                      true -> "not configured"
                    end
                  }
                  autocomplete="off"
                />
                <p
                  :if={@config.api_token_encrypted}
                  class="text-xs text-muted-foreground -mt-2"
                >
                  Token is configured and encrypted. Leave blank to keep the current value.
                </p>

                <div class="grid grid-cols-2 gap-4">
                  <.input
                    field={@form[:category_confidence_threshold]}
                    type="number"
                    label="Category confidence threshold"
                    placeholder={to_string(@env_defaults.category_confidence_threshold)}
                    step="0.01"
                    min="0.01"
                    max="0.99"
                  />
                  <.input
                    field={@form[:tag_confidence_threshold]}
                    type="number"
                    label="Tag confidence threshold"
                    placeholder={to_string(@env_defaults.tag_confidence_threshold)}
                    step="0.01"
                    min="0.01"
                    max="0.99"
                  />
                </div>
              </fieldset>
            </div>

            <:actions>
              <div class="flex items-center gap-3">
                <.button type="submit" phx-disable-with="Saving...">Save</.button>
                <.health_button status={@health} />
              </div>
            </:actions>
          </.simple_form>

          <div
            :if={@confirm_save}
            class="mt-4 rounded-lg border border-warning/50 bg-warning/10 p-4"
          >
            <p class="text-sm font-medium text-warning">
              Service is not responding at this URL. Save anyway?
            </p>
            <div class="mt-3 flex gap-2">
              <.button size="sm" variant="warning" phx-click="confirm_save">
                Save anyway
              </.button>
              <.button size="sm" variant="outline" phx-click="cancel_save">
                Cancel
              </.button>
            </div>
          </div>

          <div class="mt-4 pt-4 border-t border-border/50">
            <button
              type="button"
              class="text-xs text-muted-foreground hover:text-foreground flex items-center gap-1 transition-colors"
              phx-click="toggle_docs"
            >
              <.icon
                name={if @docs_expanded, do: "hero-chevron-down", else: "hero-chevron-right"}
                class="size-3"
              /> API endpoints
            </button>
            <div :if={@docs_expanded} class="mt-2 rounded-lg bg-shad-muted/50 p-3">
              <table class="w-full text-xs">
                <tbody>
                  <tr class="border-b border-border/50">
                    <td class="py-1.5 pr-2 font-mono font-medium text-shad-primary">POST</td>
                    <td class="py-1.5 pr-3 font-mono">/predict/category</td>
                    <td class="py-1.5 text-muted-foreground">
                      JSON input → predicted category + confidence
                    </td>
                  </tr>
                  <tr class="border-b border-border/50">
                    <td class="py-1.5 pr-2 font-mono font-medium text-shad-primary">POST</td>
                    <td class="py-1.5 pr-3 font-mono">/predict/tag</td>
                    <td class="py-1.5 text-muted-foreground">
                      JSON input → predicted tag + confidence
                    </td>
                  </tr>
                  <tr>
                    <td class="py-1.5 pr-2 font-mono font-medium text-shad-primary">GET</td>
                    <td class="py-1.5 pr-3 font-mono">/health</td>
                    <td class="py-1.5 text-muted-foreground">Returns 200 with JSON status</td>
                  </tr>
                </tbody>
              </table>
              <p class="mt-2 text-xs text-muted-foreground">
                Full documentation:
                <a
                  href="https://github.com/appunite/au-payroll-model-categories"
                  target="_blank"
                  rel="noopener"
                  class="text-shad-primary hover:underline"
                >
                  github.com/appunite/au-payroll-model-categories
                  <.icon name="hero-arrow-top-right-on-square" class="size-3 inline" />
                </a>
              </p>
            </div>
          </div>
        </div>
      </div>
    </.settings_layout>
    """
  end

  attr :status, :any, required: true

  @spec health_button(map()) :: Phoenix.LiveView.Rendered.t()
  defp health_button(assigns) do
    {variant, label} =
      case assigns.status do
        :checking -> {"outline", "Checking…"}
        :ok -> {"success", "Healthy"}
        {:error, _} -> {"outline-destructive", "Unreachable"}
        _ -> {"outline", "Check Health"}
      end

    assigns =
      assign(assigns, variant: variant, label: label, checking: assigns.status == :checking)

    ~H"""
    <.button
      type="button"
      variant={@variant}
      phx-click="check_health"
      disabled={@checking}
    >
      <.icon
        name="hero-arrow-path"
        class={"size-4 #{if @checking, do: "motion-safe:animate-spin"}"}
      /> {@label}
    </.button>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("validate", %{"classifier" => params}, socket) do
    changeset =
      socket.assigns.config
      |> ClassifierConfig.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :classifier))}
  end

  @impl true
  def handle_event("save", %{"classifier" => params}, socket) do
    # Blank token means "keep existing"
    params =
      case params["api_token"] do
        nil -> Map.delete(params, "api_token")
        "" -> Map.delete(params, "api_token")
        _ -> params
      end

    # Health check the URL before saving (only if enabled with a custom URL)
    url = resolve_check_url(params, socket)

    if url do
      Task.Supervisor.async_nolink(KsefHub.TaskSupervisor, fn ->
        {:pre_save_health, params, check_url_health(url)}
      end)

      {:noreply, assign(socket, health: :checking)}
    else
      do_save(socket, params)
    end
  end

  @impl true
  def handle_event("confirm_save", _params, socket) do
    do_save(socket, socket.assigns.pending_params)
  end

  @impl true
  def handle_event("cancel_save", _params, socket) do
    {:noreply, assign(socket, confirm_save: false, pending_params: nil)}
  end

  @impl true
  def handle_event("check_health", _params, socket) do
    check_health_async(socket.assigns.config, socket.assigns.env_defaults)
    {:noreply, assign(socket, health: :checking)}
  end

  @impl true
  def handle_event("toggle_docs", _params, socket) do
    {:noreply, assign(socket, docs_expanded: !socket.assigns.docs_expanded)}
  end

  # --- Async results ---

  @impl true
  def handle_info({ref, {:health_result, result}}, socket) do
    Process.demonitor(ref, [:flush])
    {:noreply, assign(socket, health: if(result == :ok, do: :ok, else: {:error, result}))}
  end

  @impl true
  def handle_info({ref, {:pre_save_health, params, health_result}}, socket) do
    Process.demonitor(ref, [:flush])

    socket =
      assign(socket, health: if(health_result == :ok, do: :ok, else: {:error, health_result}))

    case health_result do
      :ok -> do_save(socket, params)
      _error -> {:noreply, assign(socket, confirm_save: true, pending_params: params)}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket), do: {:noreply, socket}

  # --- Private ---

  @spec do_save(Phoenix.LiveView.Socket.t(), map()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_save(socket, params) do
    params = Map.put(params, "updated_by_id", socket.assigns.current_user.id)

    case ServiceConfig.update_classifier_config(socket.assigns.config, params) do
      {:ok, updated} ->
        env = ServiceConfig.env_defaults()

        {:noreply,
         socket
         |> put_flash(:info, "Classifier configuration saved.")
         |> assign(
           config: updated,
           form: build_form(updated, env),
           confirm_save: false,
           pending_params: nil
         )}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(
           form: to_form(changeset, as: :classifier),
           confirm_save: false,
           pending_params: nil
         )}
    end
  end

  @spec build_form(ClassifierConfig.t(), map()) :: Phoenix.HTML.Form.t()
  defp build_form(config, env) do
    attrs = %{
      "enabled" => config.enabled,
      "url" => config.url || env.url,
      "category_confidence_threshold" =>
        config.category_confidence_threshold || env.category_confidence_threshold,
      "tag_confidence_threshold" =>
        config.tag_confidence_threshold || env.tag_confidence_threshold
    }

    config
    |> ClassifierConfig.changeset(attrs)
    |> Map.put(:action, nil)
    |> to_form(as: :classifier)
  end

  @spec resolve_check_url(map(), Phoenix.LiveView.Socket.t()) :: String.t() | nil
  defp resolve_check_url(params, socket) do
    enabled = params["enabled"] in ["true", true]
    url = params["url"]

    cond do
      enabled && is_binary(url) && url != "" -> url
      enabled -> socket.assigns.config.url || socket.assigns.env_defaults.url
      true -> nil
    end
  end

  @spec check_health_async(ClassifierConfig.t(), map()) :: :ok
  defp check_health_async(config, env) do
    url = if config.enabled, do: config.url, else: env.url

    if url do
      Task.Supervisor.async_nolink(KsefHub.TaskSupervisor, fn ->
        {:health_result, check_url_health(url)}
      end)
    else
      send(self(), {make_ref(), {:health_result, {:error, :not_configured}}})
    end

    :ok
  end

  @spec check_url_health(String.t()) :: :ok | {:error, term()}
  defp check_url_health(url) do
    case Req.get(
           url: String.trim_trailing(url, "/") <> "/health",
           receive_timeout: 5_000,
           retry: false,
           connect_options: [timeout: 3_000]
         ) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
end
