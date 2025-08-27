defmodule Wordgo.WordToVec.TestEmbeddings do
  @moduledoc """
  Module for testing the embedding functionality.
  This module provides simple functions to test that the embedding service
  is working correctly and to validate similarity calculations.
  """

  alias Wordgo.WordToVec.GetScore

  @doc """
  Runs a test of embedding similarity between the provided words.
  If no words are provided, uses default test pairs.
  Returns a list of word pairs and their similarity scores.
  """
  def test_similarity(word_pairs \\ nil) do
    pairs = word_pairs || default_test_pairs()

    Enum.map(pairs, fn {word1, word2} ->
      score = GetScore.run(word1, word2)
      # IO.puts("Similarity between '#{word1}' and '#{word2}': #{score}")
      {word1, word2, score}
    end)
  end

  @doc """
  Default word pairs for testing semantic similarity.
  These pairs are arranged from likely high similarity to low similarity.
  """
  def default_test_pairs do
    [
      {"cat", "kitten"},
      {"dog", "puppy"},
      {"happy", "joy"},
      {"sad", "unhappy"},
      {"king", "queen"},
      {"man", "woman"},
      {"good", "bad"},
      {"computer", "keyboard"},
      {"tree", "forest"},
      {"car", "automobile"},
      {"water", "fire"},
      {"elephant", "refrigerator"}
    ]
  end

  @doc """
  Tests the raw embedding functionality without computing similarity.
  Returns the embedding vector for the given word.
  """
  def test_embedding(word) do
    embedding = GetScore.get_embedding([word])
    shape = Nx.shape(List.first(embedding))

    IO.puts("Successfully generated embedding for '#{word}'")
    IO.puts("Embedding shape: #{inspect(shape)}")
    IO.puts("First 5 values: #{inspect(Nx.to_flat_list(embedding) |> Enum.take(5))}")

    embedding
  end
end
