defmodule Wordgo.WordToVec.Embeddings do
  @moduledoc """
  Module for loading and serving a text embedding model using Bumblebee.
  This module provides functionality to convert words to vector embeddings
  that can be used for semantic similarity calculations.
  """

  alias Nx.Serving
  require Logger

  @doc """
  Returns the serving for the embedding model.
  This function is called by the application supervisor to start the serving.
  """
  def serving do
    {:ok, model_info} = Bumblebee.load_model({:hf, "BAAI/bge-small-en-v1.5"})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, "BAAI/bge-small-en-v1.5"})

    Bumblebee.Text.TextEmbedding.text_embedding(model_info, tokenizer,
      compile: [batch_size: 8, sequence_length: 8],
      defn_options: [compiler: EXLA],
      preallocate_params: true
    )
  end

  @doc """
  Starts the embedding serving and registers it with the given name.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, Wordgo.Embeddings)
    Logger.info("Starting embedding model serving: #{inspect(name)}")

    # Create the serving
    serving = serving()

    # Start a supervised Nx.Serving process with our model
    Serving.start_link(
      name: name,
      serving: serving,
      batch_size: 8,
      batch_timeout: 100
    )
  end

  @doc """
  Generates an embedding for a given text using the serving.
  """
  def embed_text(text, opts \\ []) do
    name = Keyword.get(opts, :name, Wordgo.Embeddings)
    Serving.batched_run(name, text)
  end
end
