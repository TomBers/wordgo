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
    opts = Application.get_env(:wordgo, :embeddings, [])

    model = Keyword.get(opts, :model, "BAAI/bge-small-en-v1.5")
    batch_size = Keyword.get(opts, :batch_size, 16)
    sequence_length = Keyword.get(opts, :sequence_length, 16)
    output_attribute = Keyword.get(opts, :output_attribute, :hidden_state)
    output_pool = Keyword.get(opts, :output_pool, :mean_pooling)

    {:ok, model_info} = Bumblebee.load_model({:hf, model})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, model})

    Bumblebee.Text.TextEmbedding.text_embedding(model_info, tokenizer,
      compile: [batch_size: batch_size, sequence_length: sequence_length],
      defn_options: [compiler: EXLA],
      output_attribute: output_attribute,
      output_pool: output_pool,
      preallocate_params: true
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
