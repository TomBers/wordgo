defmodule Wordgo.Test.Mocks.WordEmbeddingsMock do
  @moduledoc """
  Provides mocking functionality for word embeddings during testing.
  This avoids the need to make real API calls to Hugging Face
  during test runs.
  """

  # alias Nx.Tensor

  @doc """
  Returns a mock serving for testing, which produces deterministic
  embeddings instead of calling the real model.
  """
  def serving do
    # Return a simple function that creates fake embeddings
    fn inputs ->
      # Generate predictable, deterministic embeddings based on the input text
      embeddings = generate_mock_embeddings(inputs)

      # Match the output format expected by the application
      %{
        embeddings: embeddings
      }
    end
  end

  @doc """
  Generates mock embeddings for the input text.
  For testing, we just need consistent vectors that allow
  semantic similarity to work predictably.
  """
  def generate_mock_embeddings(text) when is_binary(text) do
    # Hash the text to get a deterministic seed
    seed = :erlang.phash2(text, 1000)

    # Create a fake embedding with 384 dimensions (same as bge-small)
    vector = create_vector_from_seed(seed, 384)

    # Return as tensor with the right shape
    Nx.tensor([vector])
  end

  def generate_mock_embeddings(texts) when is_list(texts) do
    # Process each text and stack the results
    embeddings =
      Enum.map(texts, fn text ->
        seed = :erlang.phash2(text, 1000)
        create_vector_from_seed(seed, 384)
      end)

    Nx.tensor(embeddings)
  end

  # Create a vector with values derived from the seed
  defp create_vector_from_seed(seed, size) do
    :rand.seed(:exsss, {seed, seed, seed})

    # Generate a normalized vector
    vector = for _ <- 1..size, do: :rand.uniform() - 0.5
    total = :math.sqrt(Enum.sum(Enum.map(vector, fn x -> x * x end)))

    # Normalize to unit length
    Enum.map(vector, fn x -> x / total end)
  end
end
