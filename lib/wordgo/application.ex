defmodule Wordgo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      WordgoWeb.Telemetry,
      Wordgo.Repo,
      {DNSCluster, query: Application.get_env(:wordgo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Wordgo.PubSub},
      Wordgo.Readiness,
      # Start the HTTP endpoint early so Fly's proxy sees a listener quickly
      WordgoWeb.Endpoint,

      # Start the embedding model server without blocking endpoint startup
      {Wordgo.WordToVec.Embeddings, name: Wordgo.Embeddings},

      # Background warm-up task to compile the model/JIT ahead of first request
      %{
        id: Wordgo.EmbeddingsWarmup,
        start: {Task, :start_link, [fn -> warmup_embeddings!() end]},
        restart: :transient
      }
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Wordgo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp warmup_embeddings!() do
    name = Wordgo.Embeddings
    if Code.ensure_loaded?(Wordgo.Readiness), do: Wordgo.Readiness.set_warming()

    # Wait up to 60s for the serving to start
    :ok = wait_until(fn -> Process.whereis(name) end, 60_000)

    # Trigger a first run to compile JIT and warm caches; ignore the result
    try do
      _ = Nx.Serving.batched_run(name, "warmup")
      Logger.info("Embeddings serving warmed up")
      if Code.ensure_loaded?(Wordgo.Readiness), do: Wordgo.Readiness.set_ready()
    catch
      kind, reason ->
        Logger.info("Embeddings warm-up skipped (#{inspect(kind)}): #{inspect(reason)}")
        if Code.ensure_loaded?(Wordgo.Readiness), do: Wordgo.Readiness.set_error({kind, reason})
    end
  end

  defp wait_until(pred, timeout_ms) when is_function(pred, 0) and is_integer(timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until(pred, deadline)
  end

  defp do_wait_until(pred, deadline) do
    if pred.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        :ok
      else
        Process.sleep(50)
        do_wait_until(pred, deadline)
      end
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WordgoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
