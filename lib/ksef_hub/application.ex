defmodule KsefHub.Application do
  @moduledoc "OTP Application supervisor for KSeF Hub."

  use Application

  require Logger

  @impl true
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    ksef_url = Application.get_env(:ksef_hub, :ksef_api_url, "https://api-test.ksef.mf.gov.pl")
    Logger.info("KSeF API URL configured: #{ksef_url}")

    children = [
      KsefHubWeb.Telemetry,
      KsefHub.Repo,
      {DNSCluster, query: Application.get_env(:ksef_hub, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: KsefHub.PubSub},
      {Task.Supervisor, name: KsefHub.TaskSupervisor},
      {Registry, keys: :unique, name: KsefHub.TokenManagerRegistry},
      {DynamicSupervisor, name: KsefHub.TokenManagerSupervisor, strategy: :one_for_one},
      {Oban, Application.fetch_env!(:ksef_hub, Oban)},
      KsefHubWeb.Endpoint,
      KsefHub.ServiceHealthCheck
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: KsefHub.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  @spec config_change(keyword(), keyword(), [atom()]) :: :ok
  def config_change(changed, _new, removed) do
    KsefHubWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
