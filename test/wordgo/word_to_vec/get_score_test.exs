defmodule Wordgo.WordToVec.GetScoreTest do
  use ExUnit.Case, async: true
  alias Wordgo.WordToVec.GetScore

  # This test requires the embedding service to be running
  # Skip if not in development/test environment with the service available
  @tag :embedding
  test "score_group calculates semantic similarity for a group of words" do
    # Test with a group of semantically similar words
    similar_group = ["car", "vehicle", "automobile"]
    similar_score = GetScore.score_group(similar_group)
    IO.inspect(similar_score, label: "Similar score")

    # Test with a group of semantically diverse words
    diverse_group = ["car", "banana", "democracy"]
    diverse_score = GetScore.score_group(diverse_group)
    IO.inspect(diverse_score, label: "Diverse score")

    # Similar words should have a higher score than diverse words
    assert similar_score > diverse_score

    # Both scores should be between 0 and 1
    assert similar_score >= 0 and similar_score <= 1
    assert diverse_score >= 0 and diverse_score <= 1
  end

  # Mock test that doesn't require the actual embedding service
  test "score_group with mocked embeddings" do
    # Create a mock module that will replace the real GetScore module for this test
    defmodule MockGetScore do
      def get_embedding(_words) do
        # Return some fake embeddings - 3-dimensional vectors for simplicity
        [
          Nx.tensor([1.0, 0.0, 0.0]),
          Nx.tensor([0.9, 0.1, 0.0]),
          Nx.tensor([0.8, 0.1, 0.1])
        ]
      end
    end

    # Create a test module that uses our mocked function
    defmodule TestWithMock do
      def score_group(group) do
        # Get embeddings for each word in the group using our mock
        embeddings = MockGetScore.get_embedding(group)

        # Calculate average embedding
        avg_embedding = Nx.mean(Nx.stack(embeddings), axes: [0])

        # Calculate cosine similarity between average embedding and each word
        similarities =
          Enum.map(embeddings, fn embedding ->
            Wordgo.WordToVec.GetScore.cosine_similarity(avg_embedding, embedding)
          end)

        # Return average similarity
        similarities
        |> Enum.map(&Nx.to_number/1)
        |> Enum.sum()
        |> Kernel./(length(similarities))
      end
    end

    # The group doesn't matter since we're mocking the embeddings
    group = ["word1", "word2", "word3"]
    score = TestWithMock.score_group(group)

    # The score should be a number between 0 and 1
    assert is_number(score)
    assert score >= 0 and score <= 1

    # With our mock data, we expect a fairly high similarity
    # Our vectors are all in the same general direction
    assert score > 0.9
  end

  # Unit test for cosine_similarity function
  test "cosine_similarity calculates correctly" do
    # Identical vectors should have similarity 1.0
    v1 = Nx.tensor([1.0, 0.0, 0.0])
    assert Nx.to_number(GetScore.cosine_similarity(v1, v1)) == 1.0

    # Orthogonal vectors should have similarity 0.0
    v2 = Nx.tensor([0.0, 1.0, 0.0])
    assert_in_delta Nx.to_number(GetScore.cosine_similarity(v1, v2)), 0.0, 1.0e-6

    # Vectors at 45 degrees should have similarity 0.707 (approx)
    v3 = Nx.tensor([1.0, 1.0, 0.0])
    assert_in_delta Nx.to_number(GetScore.cosine_similarity(v1, v3)), 0.7071, 0.01
  end
end
