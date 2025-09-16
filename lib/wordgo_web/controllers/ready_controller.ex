defmodule WordgoWeb.ReadyController do
  use WordgoWeb, :controller

  @doc """
  Returns 200 when the app is ready to receive traffic, otherwise 503.

  Readiness is considered true if:
    - Wordgo.Readiness.ready?/0 exists and returns true, or
    - the Wordgo.Embeddings Nx.Serving process is started (best-effort fallback)

  This endpoint is intended for Fly.io (or similar) readiness checks.
  """
  def ready(conn, _params) do
    if ready?() do
      conn
      |> put_resp_content_type("text/plain")
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(200, "ok")
    else
      conn
      |> put_resp_content_type("text/plain")
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(503, "warming")
    end
  end

  # -- Internals

  defp ready? do
    readiness_ready?() or embeddings_ready?()
  end

  defp readiness_ready? do
    Code.ensure_loaded?(Wordgo.Readiness) and
      function_exported?(Wordgo.Readiness, :ready?, 0) and
      safe_ready_call()
  end

  defp safe_ready_call do
    try do
      apply(Wordgo.Readiness, :ready?, [])
    rescue
      _ -> false
    catch
      _, _ -> false
    end
  end

  defp embeddings_ready? do
    # Consider the app "ready enough" if the serving process is started.
    # If you strictly want to wait for model warm-up, prefer Wordgo.Readiness.
    Process.whereis(Wordgo.Embeddings) != nil
  end
end
