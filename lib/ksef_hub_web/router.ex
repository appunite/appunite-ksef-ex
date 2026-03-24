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

  # Public shareable invoice routes (no auth required)
  scope "/public", KsefHubWeb do
    pipe_through :browser

    live_session :public_invoice,
      on_mount: [{KsefHubWeb.LiveAuth, :mount_current_user}],
      layout: {KsefHubWeb.Layouts, :public} do
      live "/invoices/:id", InvoiceLive.PublicShow
    end

    get "/invoices/:id/pdf", PublicInvoicePdfController, :show
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

    live_session :require_create_invoice,
      on_mount: [
        {KsefHubWeb.LiveAuth, :default},
        {KsefHubWeb.LiveAuth, {:require_permission, :create_invoice}}
      ] do
      live "/invoices/upload", InvoiceLive.Upload
    end

    live_session :authenticated, on_mount: {KsefHubWeb.LiveAuth, :default} do
      live "/dashboard", DashboardLive
      live "/invoices", InvoiceLive.Index
      live "/invoices/:id", InvoiceLive.Show
      live "/invoices/:id/classify", InvoiceLive.Classify
    end

    live_session :require_manage_tokens,
      on_mount: [
        {KsefHubWeb.LiveAuth, :default},
        {KsefHubWeb.LiveAuth, {:require_permission, :manage_tokens}}
      ] do
      live "/tokens", TokenLive
    end

    live_session :require_view_syncs,
      on_mount: [
        {KsefHubWeb.LiveAuth, :default},
        {KsefHubWeb.LiveAuth, {:require_permission, :view_syncs}}
      ] do
      live "/syncs", SyncLive
    end

    live_session :require_view_exports,
      on_mount: [
        {KsefHubWeb.LiveAuth, :default},
        {KsefHubWeb.LiveAuth, {:require_permission, :view_exports}}
      ] do
      live "/exports", ExportLive.Index
    end

    live_session :require_manage_certificates,
      on_mount: [
        {KsefHubWeb.LiveAuth, :default},
        {KsefHubWeb.LiveAuth, {:require_permission, :manage_certificates}}
      ] do
      live "/certificates", CertificateLive
    end

    live_session :require_manage_categories,
      on_mount: [
        {KsefHubWeb.LiveAuth, :default},
        {KsefHubWeb.LiveAuth, {:require_permission, :manage_categories}}
      ] do
      live "/categories", CategoryLive.Index, :index
      live "/categories/new", CategoryLive.Form, :new
      live "/categories/:id/edit", CategoryLive.Form, :edit
    end

    live_session :require_manage_tags,
      on_mount: [
        {KsefHubWeb.LiveAuth, :default},
        {KsefHubWeb.LiveAuth, {:require_permission, :manage_tags}}
      ] do
      live "/tags", TagLive.Index, :index
      live "/tags/new", TagLive.Form, :new
      live "/tags/:id/edit", TagLive.Form, :edit
    end

    live_session :require_manage_team,
      on_mount: [
        {KsefHubWeb.LiveAuth, :default},
        {KsefHubWeb.LiveAuth, {:require_permission, :manage_team}}
      ] do
      live "/team", TeamLive
    end

    live_session :require_view_payment_requests,
      on_mount: [
        {KsefHubWeb.LiveAuth, :default},
        {KsefHubWeb.LiveAuth, {:require_permission, :view_payment_requests}}
      ] do
      live "/payment-requests", PaymentRequestLive.Index
    end

    live_session :require_manage_payment_requests,
      on_mount: [
        {KsefHubWeb.LiveAuth, :default},
        {KsefHubWeb.LiveAuth, {:require_permission, :manage_payment_requests}}
      ] do
      live "/payment-requests/new", PaymentRequestLive.Form, :new
      live "/payment-requests/:id/edit", PaymentRequestLive.Form, :edit
    end

    get "/payment-requests/csv", PaymentRequestCsvController, :download
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
    post "/invoices/:id/reset_status", InvoiceController, :reset_status
    post "/invoices/:id/confirm-duplicate", InvoiceController, :confirm_duplicate
    post "/invoices/:id/dismiss-duplicate", InvoiceController, :dismiss_duplicate
    get "/invoices/:id/html", InvoiceController, :html
    get "/invoices/:id/pdf", InvoiceController, :pdf
    get "/invoices/:id/xml", InvoiceController, :xml
    put "/invoices/:id/category", InvoiceController, :set_category
    put "/invoices/:id/tags", InvoiceController, :set_tags
    get "/invoices/:id/access", InvoiceController, :get_access
    put "/invoices/:id/access", InvoiceController, :set_access
    post "/invoices/:id/access/grants", InvoiceController, :grant_access
    delete "/invoices/:id/access/grants/:user_id", InvoiceController, :revoke_access

    resources "/categories", CategoryController, except: [:new, :edit]
    resources "/tags", TagController, except: [:new, :edit]

    resources "/tokens", TokenController, only: [:index, :create, :delete]

    resources "/payment-requests", PaymentRequestController, only: [:index, :create]
    post "/payment-requests/:id/mark-paid", PaymentRequestController, :mark_paid
    post "/payment-requests/:id/void", PaymentRequestController, :void
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
