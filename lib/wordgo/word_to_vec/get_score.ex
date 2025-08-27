defmodule Wordgo.WordToVec.GetScore do
  @moduledoc """
  Module for calculating semantic similarity between words using Bumblebee.
  """

  alias Nx.Serving
  require Logger

  def run do
    run("Bob", "Bill")
  end

  @doc """
  Calculates the semantic similarity between two words using embeddings.
  Returns a float value between 0 and 1, where higher values indicate greater similarity.
  """
  def run(word1, word2) do
    # Get embeddings for both words
    embeddings = get_embedding([word1, word2])

    # Calculate cosine similarity
    similarity = cosine_similarity(List.first(embeddings), List.last(embeddings))

    # Convert to float and return
    Nx.to_number(similarity)
  rescue
    e ->
      Logger.error("Error calculating similarity: #{inspect(e)}")
      fallback_similarity(word1, word2)
  end

  @doc """
  Gets the embedding vector for a given words.
  """
  def get_embedding(words) do
    case Serving.batched_run(Wordgo.Embeddings, words) do
      tensors ->
        Enum.map(tensors, fn %{embedding: embedding} -> embedding end)

        # result ->
        #   Logger.error("Unexpected embedding result: #{inspect(result)}")
        #   raise "Failed to get embedding for word: #{words}"
    end
  end

  @doc """
  Calculates cosine similarity between two embedding vectors.
  """
  def cosine_similarity(vector1, vector2) do
    # Normalize vectors
    norm1 = Nx.sqrt(Nx.sum(Nx.multiply(vector1, vector1)))
    norm2 = Nx.sqrt(Nx.sum(Nx.multiply(vector2, vector2)))

    # Dot product of normalized vectors
    dot_product = Nx.sum(Nx.multiply(vector1, vector2))

    # Cosine similarity
    Nx.divide(dot_product, Nx.multiply(norm1, norm2))
  end

  @doc """
  Fallback method to use if the embedding service is not available.
  """
  def fallback_similarity(word1, word2) do
    try do
      # Try to use the external service as fallback
      url = "http://localhost:8000"
      path = "/similarity/#{word1}/#{word2}"
      Req.get!(url <> path).body["similarity"]
    rescue
      e ->
        Logger.error("Fallback similarity failed: #{inspect(e)}")
        # If all else fails, return string equality (0 or 1)
        if word1 == word2, do: 1.0, else: 0.0
    end
  end
end
