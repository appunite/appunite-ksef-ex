defmodule KsefHubWeb.Router do
  use KsefHubWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KsefHubWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :require_auth do
    plug KsefHubWeb.Plugs.RequireAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: KsefHubWeb.ApiSpec
  end

  pipeline :api_auth do
    plug KsefHubWeb.Plugs.ApiAuth
  end

  pipeline :webhook do
    plug :accepts, ["json", "html"]
  end

  # Health check (no pipeline — used by Cloud Run probes)
  scope "/healthz" do
    get "/", KsefHubWeb.HealthController, :index
    get "/services", KsefHubWeb.HealthController, :services
  end

  # Webhook routes (no CSRF, no session, no auth — signature-verified)
  scope "/webhooks", KsefHubWeb do
    pipe_through :webhook

    post "/mailgun/inbound", WebhookController, :inbound
  end

  # Public browser routes
  scope "/", KsefHubWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # OAuth routes
  scope "/auth", KsefHubWeb do
    pipe_through :browser

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  # Auth routes (email/password)
  scope "/", KsefHubWeb do
    pipe_through :browser

    live_session :redirect_if_authenticated,
      on_mount: [{KsefHubWeb.LiveAuth, :redirect_if_authenticated}] do
      live "/users/register", UserRegistrationLive
      live "/users/log-in", UserLoginLive
      live "/users/reset-password", UserForgotPasswordLive
      live "/users/reset-password/:token", UserResetPasswordLive
    end

    live_session :confirm_user,
      on_mount: [{KsefHubWeb.LiveAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive
      live "/users/confirm", UserConfirmationInstructionsLive
      live "/invitations/accept/:token", InvitationAcceptLive
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  # Protected browser routes (LiveView admin UI)
  scope "/", KsefHubWeb do
    pipe_through [:browser, :require_auth]

    # Company management routes (not company-scoped)
    live_session :authenticated_top, on_mount: {KsefHubWeb.LiveAuth, :default} do
      live "/companies", CompanyLive.Index
      live "/companies/new", CompanyLive.Index, :new
      live "/companies/:id/edit", CompanyLive.Index, :edit
    end

    post "/switch-company/:id", CompanySwitchController, :update
  end

  # Company-scoped routes
  scope "/c/:company_id", KsefHubWeb do
    pipe_through [:browser, :require_auth]

    live_session :authenticated, on_mount: {KsefHubWeb.LiveAuth, :default} do
      live "/dashboard", DashboardLive
      live "/invoices", InvoiceLive.Index
      live "/invoices/upload", InvoiceLive.Upload
      live "/invoices/:id", InvoiceLive.Show
      live "/tokens", TokenLive
      live "/syncs", SyncLive
      live "/exports", ExportLive.Index
    end

    live_session :admin_only,
      on_mount: [{KsefHubWeb.LiveAuth, :default}, {KsefHubWeb.LiveAuth, :require_admin}] do
      live "/certificates", CertificateLive
      live "/categories", CategoryLive
      live "/tags", TagLive
      live "/team", TeamLive
    end

    get "/invoices/:id/pdf", InvoicePdfController, :show
    get "/invoices/:id/xml", InvoicePdfController, :xml
    get "/exports/:id/download", ExportController, :download
  end

  # OpenAPI spec (public, no auth required)
  scope "/api" do
    pipe_through :api

    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
  end

  # API routes (bearer token auth)
  scope "/api", KsefHubWeb.Api do
    pipe_through [:api, :api_auth]

    resources "/invoices", InvoiceController, only: [:index, :show, :create]
    post "/invoices/upload", InvoiceController, :upload
    patch "/invoices/:id", InvoiceController, :update
    post "/invoices/:id/approve", InvoiceController, :approve
    post "/invoices/:id/reject", InvoiceController, :reject
    post "/invoices/:id/confirm-duplicate", InvoiceController, :confirm_duplicate
    post "/invoices/:id/dismiss-duplicate", InvoiceController, :dismiss_duplicate
    get "/invoices/:id/html", InvoiceController, :html
    get "/invoices/:id/pdf", InvoiceController, :pdf
    get "/invoices/:id/xml", InvoiceController, :xml
    put "/invoices/:id/category", InvoiceController, :set_category
    put "/invoices/:id/tags", InvoiceController, :set_tags

    resources "/categories", CategoryController, except: [:new, :edit]
    resources "/tags", TagController, except: [:new, :edit]

    resources "/tokens", TokenController, only: [:index, :create, :delete]
  end

  # Enable LiveDashboard, Swoosh mailbox, and SwaggerUI in development
  if Application.compile_env(:ksef_hub, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: KsefHubWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview

      get "/swaggerui", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi"
    end
  end
end
