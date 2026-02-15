# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Register certificate-related MIME types for upload validation
config :mime, :types, %{
  "application/x-pkcs12" => ["p12", "pfx"],
  "application/x-pem-file" => ["pem", "key"],
  "application/x-x509-ca-cert" => ["crt", "cer"]
}

config :ksef_hub,
  ecto_repos: [KsefHub.Repo],
  generators: [timestamp_type: :utc_datetime],
  ksef_client: KsefHub.KsefClient.Live,
  xades_signer: KsefHub.XadesSigner.Native,
  pkcs12_converter: KsefHub.Credentials.Pkcs12Converter.Openssl,
  ksef_api_url: "https://api-test.ksef.mf.gov.pl"

# Oban background jobs
config :ksef_hub, Oban,
  repo: KsefHub.Repo,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"*/15 * * * *", KsefHub.Sync.SyncDispatcher}
     ]},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(15)}
  ],
  queues: [sync: 1, default: 5]

# Google OAuth
config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, [default_scope: "email profile"]}
  ]

# Configures the endpoint
config :ksef_hub, KsefHubWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: KsefHubWeb.ErrorHTML, json: KsefHubWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: KsefHub.PubSub,
  live_view: [signing_salt: "KgtXyLaU"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :ksef_hub, KsefHub.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  ksef_hub: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  ksef_hub: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
