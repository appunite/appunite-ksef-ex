defmodule KsefHub.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      KsefHubWeb.Telemetry,
      KsefHub.Repo,
      {DNSCluster, query: Application.get_env(:ksef_hub, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: KsefHub.PubSub},
      # Start a worker by calling: KsefHub.Worker.start_link(arg)
      # {KsefHub.Worker, arg},
      # Start to serve requests, typically the last entry
      KsefHubWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: KsefHub.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    KsefHubWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
