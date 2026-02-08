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
  end

  pipeline :api_auth do
    plug KsefHubWeb.Plugs.ApiAuth
  end

  # Health check (no pipeline — used by Cloud Run probes)
  scope "/healthz" do
    get "/", KsefHubWeb.HealthController, :index
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
    delete "/logout", AuthController, :logout
  end

  # Protected browser routes (LiveView admin UI)
  scope "/", KsefHubWeb do
    pipe_through [:browser, :require_auth]

    live_session :authenticated, on_mount: {KsefHubWeb.LiveAuth, :default} do
      live "/dashboard", DashboardLive
      live "/certificates", CertificateLive
      live "/invoices", InvoiceLive.Index
      live "/invoices/:id", InvoiceLive.Show
      live "/tokens", TokenLive
      live "/syncs", SyncLive
      live "/companies", CompanyLive.Index
      live "/companies/new", CompanyLive.Index, :new
      live "/companies/:id/edit", CompanyLive.Index, :edit
    end

    post "/switch-company/:id", CompanySwitchController, :update
    get "/switch-company/:id", CompanySwitchController, :update
    get "/invoices/:id/pdf", InvoicePdfController, :show
  end

  # API routes (bearer token auth)
  scope "/api", KsefHubWeb.Api do
    pipe_through [:api, :api_auth]

    resources "/invoices", InvoiceController, only: [:index, :show] do
      post "/approve", InvoiceController, :approve
      post "/reject", InvoiceController, :reject
      get "/html", InvoiceController, :html
      get "/pdf", InvoiceController, :pdf
    end

    resources "/tokens", TokenController, only: [:index, :create, :delete]
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ksef_hub, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: KsefHubWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
