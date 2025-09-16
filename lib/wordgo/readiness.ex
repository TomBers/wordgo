defmodule Wordgo.Readiness do
  @moduledoc """
  Tracks application readiness (particularly model warm-up) via a lightweight Agent.

  States:
    - `:starting` - application booting
    - `:warming`  - Nx/Bumblebee serving is warming up / compiling
    - `:ready`    - model is warmed and the app can accept traffic
    - `{:error, reason}` - an unrecoverable error occurred during warm-up

  Add it to your supervision tree early (before the Endpoint), for example:

      children = [
        Wordgo.Readiness,
        # ... your Nx.Serving child, warm-up Task, etc ...
        WordgoWeb.Endpoint
      ]

  When you kick off warm-up, set `:warming`, and when done, set `:ready`:

      Wordgo.Readiness.set_warming()
      _ = Nx.Serving.batched_run(MyServing, warmup_payload)
      Wordgo.Readiness.set_ready()

  You can expose a readiness endpoint that returns 200 only when ready:

      if Wordgo.Readiness.ready?(), do: 200, else: 503

  Optionally, wait for readiness with a timeout at boot of components that
  must not start serving before the model is compiled:

      case Wordgo.Readiness.await_ready(60_000) do
        :ok -> :ok
        {:error, :timeout} -> # handle timeout
        {:error, reason} ->   # handle warm-up error
      end
  """

  use Agent
  require Logger

  @type status :: :starting | :warming | :ready | {:error, term()}

  @doc """
  Starts the Readiness agent.

  Options:
    - `:name` - process name (defaults to `#{__MODULE__}`)

  Initial state is `:starting`.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> :starting end, name: name)
  end

  @doc """
  Returns the current readiness status.
  """
  @spec status() :: status()
  def status, do: Agent.get(__MODULE__, & &1)

  @doc """
  True if the application is ready.
  """
  @spec ready?() :: boolean()
  def ready?, do: status() == :ready

  @doc """
  True if the application is either warming or ready.
  """
  @spec warming_or_ready?() :: boolean()
  def warming_or_ready?(), do: status() in [:warming, :ready]

  @doc """
  Sets the readiness status. Allowed values are:
  `:starting | :warming | :ready | {:error, term()}`.
  """
  @spec set_status(status()) :: :ok
  def set_status(new_status) do
    validate_status!(new_status)
    Agent.cast(__MODULE__, fn _ -> new_status end)
  end

  @doc """
  Convenience to set status to `:starting`.
  """
  @spec set_starting() :: :ok
  def set_starting, do: set_status(:starting)

  @doc """
  Convenience to set status to `:warming`.
  """
  @spec set_warming() :: :ok
  def set_warming, do: set_status(:warming)

  @doc """
  Convenience to set status to `:ready`.
  """
  @spec set_ready() :: :ok
  def set_ready, do: set_status(:ready)

  @doc """
  Sets an error status with a reason.
  """
  @spec set_error(term()) :: :ok
  def set_error(reason) do
    Logger.error("Readiness error: #{inspect(reason)}")
    set_status({:error, reason})
  end

  @doc """
  Blocks until readiness is `:ready` or an error/timeout occurs.

  Returns:
    - `:ok` on ready
    - `{:error, :timeout}` if the timeout elapses
    - `{:error, reason}` if status becomes `{:error, reason}`

  The `timeout_ms` parameter must be a positive integer (defaults to 30_000).
  """
  @spec await_ready(non_neg_integer()) :: :ok | {:error, :timeout | term()}
  def await_ready(timeout_ms \\ 30_000) when is_integer(timeout_ms) and timeout_ms >= 0 do
    start = System.monotonic_time(:millisecond)
    poll_until_ready(start, timeout_ms)
  end

  # Internal helpers

  defp poll_until_ready(start_ms, timeout_ms) do
    case status() do
      :ready ->
        :ok

      {:error, reason} ->
        {:error, reason}

      _other ->
        if elapsed_ms(start_ms) >= timeout_ms do
          {:error, :timeout}
        else
          Process.sleep(50)
          poll_until_ready(start_ms, timeout_ms)
        end
    end
  end

  defp elapsed_ms(start_ms),
    do: System.monotonic_time(:millisecond) - start_ms

  defp validate_status!(val) do
    case val do
      :starting -> :ok
      :warming -> :ok
      :ready -> :ok
      {:error, _} -> :ok
      other -> raise ArgumentError, "invalid readiness status: #{inspect(other)}"
    end
  end
end
