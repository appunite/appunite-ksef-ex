import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ksef_hub, KsefHub.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ksef_hub_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ksef_hub, KsefHubWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "kMVKgZ9vlzq0MfbOhqvq+B1lyPvmf5PIDrAAXZWSC/XK2HNwCniHD29Qf1tK9Xg/",
  server: false

# In test we don't send emails
config :ksef_hub, KsefHub.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Oban testing mode
config :ksef_hub, Oban, testing: :inline

# Use mock implementations in tests
config :ksef_hub, :ksef_client, KsefHub.KsefClient.Mock
config :ksef_hub, :xades_signer, KsefHub.XadesSigner.Mock
config :ksef_hub, :pdf_generator, KsefHub.Pdf.Mock
config :ksef_hub, :pkcs12_converter, KsefHub.Credentials.Pkcs12Converter.Mock
config :ksef_hub, :certificate_info, KsefHub.Credentials.CertificateInfo.Mock
config :ksef_hub, :prediction_client, KsefHub.Predictions.Mock

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
