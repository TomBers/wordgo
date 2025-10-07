defmodule Wordgo.WordToVec.GetScore do
  @moduledoc """
  Utilities for turning words into embedding vectors and comparing them.

  Defaults:
  - Scores are mapped to the 0..1 range using the angular transform.
  - Group scoring uses a centroid-based method by default.

  Options:
  - method: :centroid | :pairwise — choose the scoring method for groups (default: :centroid)
  - transform: :angular | :none | {:gamma, g} | {:affine, {a, b}} — choose how raw cosine is post-processed (default: :angular)
  """

  alias Nx.Serving
  require Logger

  def run do
    run("Bob", "Bill")
  end

  # Applies optional transforms to raw cosine similarity to increase contrast.
  # Defaults to :angular, which maps [-1, 1] to [0, 1] via 1 - arccos(cos)/pi.
  # Supported transforms:
  #   :none       -> return raw cosine
  #   :angular    -> 1 - arccos(cos)/pi (spreads high-cosine region)
  #   {:gamma, g} -> gamma curve on [0,1] region to pull apart high values
  #   {:affine, {a,b}} -> linear transform a*cos + b
  defp transform_similarity(cos, opts \\ []) when is_number(cos) do
    case Keyword.get(opts, :transform, :angular) do
      :none ->
        cos

      :angular ->
        c = min(max(cos, -1.0), 1.0)
        1.0 - :math.acos(c) / :math.pi()

      {:gamma, g} when is_number(g) and g > 0 ->
        # Clamp to [0,1] before gamma so negatives don't explode
        s = max(cos, 0.0)
        :math.pow(s, g)

      {:affine, {a, b}} when is_number(a) and is_number(b) ->
        a * cos + b

      _other ->
        cos
    end
  end

  # Computes the average of all pairwise similarities in the list.
  # More sensitive to outliers than centroid-based similarity.
  def pairwise_mean_similarity(words, opts \\ []) when is_list(words) do
    case get_embedding(words) do
      [] ->
        0.0

      embeddings ->
        n = length(embeddings)

        if n < 2 do
          1.0
        else
          {sum, count} =
            embeddings
            |> Enum.with_index()
            |> Enum.reduce({0.0, 0}, fn {e_i, i}, {acc, k} ->
              inner_sum =
                Enum.drop(embeddings, i + 1)
                |> Enum.reduce(0.0, fn e_j, s ->
                  sim = Nx.to_number(cosine_similarity(e_i, e_j))
                  s + transform_similarity(sim, opts)
                end)

              {acc + inner_sum, k + (n - i - 1)}
            end)

          if count > 0, do: sum / count, else: 0.0
        end
    end
  end

  # Centroid-based group scorer with per-item normalization; returns 0..1 by default (angular transform).
  def score_group(group, opts \\ []) do
    case Keyword.get(opts, :method, :centroid) do
      :pairwise ->
        pairwise_mean_similarity(group, opts)

      _ ->
        case get_embedding(group) do
          [] ->
            0.0

          [_e] ->
            # Single word is maximally similar to its centroid
            transform_similarity(1.0, opts)

          embeddings ->
            # Normalize each embedding first to avoid magnitude bias
            normed = Enum.map(embeddings, &normalize/1)
            # Compute and normalize centroid
            centroid = normalize(Nx.mean(Nx.stack(normed), axes: [0]))

            sims =
              Enum.map(normed, fn e ->
                Nx.to_number(cosine_similarity(centroid, e))
              end)

            mean = Enum.sum(sims) / length(sims)
            transform_similarity(mean, opts)
        end
    end
  end

  # Pairwise scorer helper; equivalent to score_group(group, method: :pairwise, ...).
  # Suggested usage:
  #   score_group(group, method: :pairwise, transform: :angular)
  def score_group_with_opts(group, opts \\ []) do
    pairwise_mean_similarity(group, opts)
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

    # Convert to float, apply default transform (angular -> 0..1), and return
    score = Nx.to_number(similarity)
    transform_similarity(score)
  rescue
    e ->
      Logger.error("Error calculating similarity: #{inspect(e)}")
      fallback_similarity(word1, word2)
  end

  @doc """
  Gets embedding vectors for the given words.
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

  @doc """
  Given a word and a desired cosine similarity value in [-1, 1], generate a new target embedding
  vector which has that cosine similarity with the given word's embedding.

  This returns the target embedding as an `Nx` tensor.
  """
  def generate_target_embedding(word, target_similarity) when is_binary(word) do
    [embedding] = get_embedding([word])

    a_hat = normalize(embedding)
    s = clamp_similarity(target_similarity)

    # Construct a unit vector with cosine s to a_hat
    target_unit = construct_unit_vector_with_cosine(a_hat, s)

    # Scale the unit result to roughly the same norm as the original embedding to keep magnitudes comparable
    target_norm = norm(embedding)
    unit_norm = norm(target_unit)
    Nx.multiply(target_unit, Nx.divide(target_norm, Nx.max(unit_norm, Nx.tensor(1.0e-12))))
  end

  @doc """
  Finds the nearest word(s) from the provided candidates to the synthetically generated embedding
  that has the given cosine similarity to the input `word`.

  Returns a list of `{candidate_word, similarity}` tuples sorted by similarity desc.
  Pass `top_k` in opts to control how many results you want (defaults to 1).
  """
  def word_with_desired_similarity(word, target_similarity, candidates, opts \\ []) do
    top_k = Keyword.get(opts, :top_k, 1)
    target_vec = generate_target_embedding(word, target_similarity)

    candidate_embeddings = get_embedding(candidates)

    candidates
    |> Enum.zip(candidate_embeddings)
    |> Enum.map(fn {w, emb} ->
      {w, Nx.to_number(cosine_similarity(target_vec, emb))}
    end)
    |> Enum.sort_by(fn {_w, score} -> score end, :desc)
    |> Enum.take(top_k)
  end

  @doc """
  Convenience helper that returns only the best matching word and its similarity.

  Returns `{word, similarity}` or `nil` if candidates list is empty.
  """
  def best_word_with_desired_similarity(word, target_similarity, candidates) do
    case word_with_desired_similarity(word, target_similarity, candidates, top_k: 1) do
      [{best, score}] -> {best, score}
      _ -> nil
    end
  end

  # == Internal helpers ==

  defp clamp_similarity(s) when is_number(s) do
    s
    |> min(0.999999)
    |> max(-0.999999)
  end

  defp norm(v), do: Nx.sqrt(Nx.sum(Nx.multiply(v, v)))

  defp normalize(v) do
    Nx.divide(v, Nx.max(norm(v), Nx.tensor(1.0e-12)))
  end

  defp dot(a, b), do: Nx.sum(Nx.multiply(a, b))

  # Constructs a unit vector `b_hat` such that `cos(a_hat, b_hat) == s`
  defp construct_unit_vector_with_cosine(a_hat, s) do
    # Build an auxiliary direction u that is not (or very unlikely to be) colinear with a_hat
    u0 = rotate1(a_hat)
    u_perp0 = Nx.subtract(u0, Nx.multiply(dot(a_hat, u0), a_hat))
    n0 = norm(u_perp0)

    u_hat =
      if Nx.to_number(n0) < 1.0e-8 do
        # Fallback: use a vector of ones and orthogonalize it
        ones = Nx.broadcast(Nx.tensor(1.0, type: Nx.type(a_hat)), Nx.shape(a_hat))
        u_perp1 = Nx.subtract(ones, Nx.multiply(dot(a_hat, ones), a_hat))
        n1 = norm(u_perp1)
        Nx.divide(u_perp1, Nx.max(n1, Nx.tensor(1.0e-12)))
      else
        Nx.divide(u_perp0, Nx.max(n0, Nx.tensor(1.0e-12)))
      end

    # b_hat = s*a_hat + sqrt(1 - s^2) * u_hat
    Nx.add(Nx.multiply(a_hat, s), Nx.multiply(u_hat, Nx.sqrt(1.0 - s * s)))
  end

  # Simple "rotate-left by 1" for a 1-D tensor to get a non-colinear direction
  defp rotate1(v) do
    d = elem(Nx.shape(v), 0)

    if d > 1 do
      tail = Nx.slice(v, [1], [d - 1])
      head = Nx.slice(v, [0], [1])
      Nx.concatenate([tail, head])
    else
      v
    end
  end
end
