defmodule Wordgo.Build do
  @moduledoc """
  Build-time helpers for Docker image construction.

  This module is intended to be invoked during the Docker builder stage to
  pre-populate the Bumblebee cache so the final image can run offline
  without contacting Hugging Face.

  Usage in Dockerfile (builder stage):

      # Ensure BUMBLEBEE_CACHE_DIR points inside the build context
      ENV BUMBLEBEE_CACHE_DIR=/app/priv/bumblebee-cache

      # After deps and code are available:
      RUN mix eval 'Wordgo.Build.load_bumblebee_cache()'

  You can customize the model via the WORDGO_BUMBLEBEE_MODEL env var.
  """

  @default_model "BAAI/bge-small-en-v1.5"

  @doc """
  Downloads the configured Bumblebee model and tokenizer into the cache directory.

  Honors:
    - WORDGO_BUMBLEBEE_MODEL: overrides the default model id
    - BUMBLEBEE_CACHE_DIR: where the cache is stored (recommended to set in builder)

  Raises on failure so Docker builds fail early and visibly.
  """
  def load_bumblebee_cache do
    # Ensure HTTPS is available in the build environment
    _ = Application.ensure_all_started(:ssl)
    _ = Application.ensure_all_started(:inets)

    model_id = System.get_env("WORDGO_BUMBLEBEE_MODEL") || @default_model

    # Log context
    cache_dir =
      System.get_env("BUMBLEBEE_CACHE_DIR") ||
        Application.get_env(:bumblebee, :cache_dir) ||
        "(system default)"

    IO.puts("[build] Bumblebee: model=#{inspect(model_id)}")
    IO.puts("[build] Bumblebee: cache_dir=#{inspect(cache_dir)}")
    IO.puts("[build] Bumblebee: starting download...")

    # Trigger downloads into the cache
    {:ok, _model_info} = Bumblebee.load_model({:hf, model_id})
    {:ok, _tokenizer} = Bumblebee.load_tokenizer({:hf, model_id})

    # Summarize what we have (best-effort)
    summarize_cache(cache_dir)

    IO.puts("[build] Bumblebee: cache populated successfully")
    :ok
  end

  defp summarize_cache("(system default)") do
    IO.puts("[build] Bumblebee: populated at system default cache directory")
  end

  defp summarize_cache(dir) when is_binary(dir) do
    # Avoid blowing up if path doesn't exist yet; create and count files for visibility
    File.mkdir_p!(dir)

    count =
      dir
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.reject(&File.dir?/1)
      |> length()

    IO.puts("[build] Bumblebee: cached files under #{dir}: #{count}")
  end
end
