import Config

# Load .env file in dev and test environments.
# In production, environment variables are set by the deployment platform.
if config_env() == :dev do
  for {k, v} <- Dotenvy.source!([".env", System.get_env()]) do
    System.put_env(k, v)
  end
end

if System.get_env("PHX_SERVER") do
  config :ksef_hub, KsefHubWeb.Endpoint, server: true
end

# Application-wide runtime config (all environments)
if google_client_id = System.get_env("GOOGLE_CLIENT_ID") do
  google_client_secret =
    System.get_env("GOOGLE_CLIENT_SECRET") ||
      raise """
      environment variable GOOGLE_CLIENT_SECRET is missing.
      GOOGLE_CLIENT_ID is set but GOOGLE_CLIENT_SECRET is required for OAuth to work.
      """

  config :ueberauth, Ueberauth.Strategy.Google.OAuth,
    client_id: google_client_id,
    client_secret: google_client_secret
end

if ksef_api_url = System.get_env("KSEF_API_URL") do
  config :ksef_hub, :ksef_api_url, ksef_api_url
end

if pdf_renderer_url = System.get_env("PDF_RENDERER_URL") do
  config :ksef_hub, :pdf_renderer_url, pdf_renderer_url
end

if invoice_extractor_url = System.get_env("INVOICE_EXTRACTOR_URL") do
  if config_env() == :prod do
    uri = URI.parse(invoice_extractor_url)

    if uri.scheme != "https" do
      raise """
      INVOICE_EXTRACTOR_URL must use HTTPS in production.
      Got: #{invoice_extractor_url}
      """
    end
  end

  config :ksef_hub, :invoice_extractor_url, invoice_extractor_url
end

if invoice_extractor_api_token = System.get_env("INVOICE_EXTRACTOR_API_TOKEN") do
  config :ksef_hub, :invoice_extractor_api_token, invoice_extractor_api_token
end

if prediction_service_url = System.get_env("PREDICTION_SERVICE_URL") do
  if config_env() == :prod do
    uri = URI.parse(prediction_service_url)

    if uri.scheme != "https" do
      raise """
      PREDICTION_SERVICE_URL must use HTTPS in production.
      Got: #{prediction_service_url}
      """
    end
  end

  config :ksef_hub, :prediction_service_url, prediction_service_url
end

if sync_interval_env = System.get_env("SYNC_INTERVAL_MINUTES") do
  valid_intervals = [1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30, 60]

  sync_minutes =
    with {n, ""} <- Integer.parse(sync_interval_env),
         true <- n in valid_intervals do
      n
    else
      _ ->
        raise """
        SYNC_INTERVAL_MINUTES must be a divisor of 60: #{inspect(valid_intervals)}.
        Got: #{inspect(sync_interval_env)}
        """
    end

  sync_cron = if sync_minutes == 60, do: "0 * * * *", else: "*/#{sync_minutes} * * * *"

  config :ksef_hub, Oban,
    plugins: [
      {Oban.Plugins.Cron,
       crontab: [
         {sync_cron, KsefHub.Sync.SyncDispatcher}
       ]},
      {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(15)}
    ]
end

if mailgun_signing_key = System.get_env("MAILGUN_SIGNING_KEY") do
  config :ksef_hub, :mailgun_signing_key, mailgun_signing_key
end

if inbound_email_domain = System.get_env("INBOUND_EMAIL_DOMAIN") do
  config :ksef_hub, :inbound_email_domain, inbound_email_domain
end

if inbound_allowed_sender_domain = System.get_env("INBOUND_ALLOWED_SENDER_DOMAIN") do
  config :ksef_hub, :inbound_allowed_sender_domain, inbound_allowed_sender_domain
end

if inbound_cc_email = System.get_env("INBOUND_CC_EMAIL") do
  config :ksef_hub, :inbound_cc_email, inbound_cc_email
end

if System.get_env("INBOUND_EMAIL_DOMAIN") && !System.get_env("MAILGUN_SIGNING_KEY") do
  raise """
  MAILGUN_SIGNING_KEY is required when INBOUND_EMAIL_DOMAIN is set.

  The inbound email feature needs a Mailgun signing key to verify webhook signatures.
  Set MAILGUN_SIGNING_KEY from your Mailgun dashboard (Settings > Webhooks > Signing Key).
  """
end

if credential_encryption_key = System.get_env("CREDENTIAL_ENCRYPTION_KEY") do
  case Base.decode64(credential_encryption_key) do
    {:ok, key} when byte_size(key) == 32 ->
      config :ksef_hub, :credential_encryption_key, credential_encryption_key

    {:ok, key} ->
      raise """
      CREDENTIAL_ENCRYPTION_KEY must decode to exactly 32 bytes (AES-256).
      Got #{byte_size(key)} bytes after base64-decoding.

      Generate a valid key with:
        elixir -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()'
      """

    :error ->
      raise """
      CREDENTIAL_ENCRYPTION_KEY is not valid base64.

      Generate a valid key with:
        elixir -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()'

      To migrate from SHA256-derived key, compute:
        elixir -e ':crypto.hash(:sha256, "<your SECRET_KEY_BASE>") |> Base.encode64() |> IO.puts()'
      """
  end
end

# Allow DATABASE_URL override in dev (e.g. to connect to Supabase from local machine)
if config_env() == :dev do
  if database_url = System.get_env("DATABASE_URL") do
    config :ksef_hub, KsefHub.Repo,
      url: database_url,
      ssl: [verify: :verify_none],
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")
  end
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  ksef_api_url =
    System.get_env("KSEF_API_URL") ||
      raise """
      environment variable KSEF_API_URL is missing.
      Use https://api-test.ksef.mf.gov.pl for test or https://api.ksef.mf.gov.pl for production.
      """

  uri = URI.parse(ksef_api_url)

  if uri.scheme != "https" do
    raise """
    KSEF_API_URL must use HTTPS in production.
    Got: #{ksef_api_url}
    """
  end

  config :ksef_hub, :ksef_api_url, ksef_api_url

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :ksef_hub, KsefHub.Repo,
    url: database_url,
    ssl: [verify: :verify_none],
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :ksef_hub, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :ksef_hub, KsefHubWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: [
      "//#{host}",
      "//*.run.app"
    ],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :ksef_hub, KsefHubWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :ksef_hub, KsefHubWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :ksef_hub, KsefHub.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
