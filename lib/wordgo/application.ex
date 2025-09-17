defmodule Wordgo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WordgoWeb.Telemetry,
      Wordgo.Repo,
      {DNSCluster, query: Application.get_env(:wordgo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Wordgo.PubSub},
      # Start a worker by calling: Wordgo.Worker.start_link(arg)
      # {Wordgo.Worker, arg},
      # Start the embedding model server
      {Nx.Serving,
       serving: Wordgo.WordToVec.Embeddings.serving(),
       name: Wordgo.Embeddings,
       batch_size: 16,
       batch_timeout: 50},
      # Start to serve requests, typically the last entry
      WordgoWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Wordgo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WordgoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
