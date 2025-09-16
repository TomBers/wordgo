defmodule Wordgo.WordToVec.Vocabulary do
  @moduledoc """
  Global vocabulary utilities for working with word embeddings.

  Features:
  - Maintain a global vocabulary list
  - Cache embeddings for vocabulary words (ETS-backed)
  - Find words closest to a synthetic embedding that has a desired cosine similarity
    to a given query word

  Notes:
  - By default, a small built-in English vocabulary is provided. You can replace it
    at runtime with `set_vocabulary/1` or `load_vocabulary_from_file!/1`.
  - Call `precompute_embeddings!/0` to batch-embed and cache the vocabulary for faster queries.
  """

  alias Wordgo.WordToVec.GetScore
  require Logger

  @table :wordgo_vocab_cache

  # -- Public API --

  @doc """
  Returns the current vocabulary list. If none has been set, returns a default list.
  """
  def get_vocabulary do
    ensure_table!()

    case :ets.lookup(@table, :vocabulary) do
      [{:vocabulary, words}] when is_list(words) ->
        words

      _ ->
        default_vocabulary()
    end
  end

  @doc """
  Replaces the current vocabulary with the provided list of words.
  This will also clear any previously cached embeddings.

  Returns :ok.
  """
  def set_vocabulary(words) when is_list(words) do
    ensure_table!()

    words =
      words
      |> Enum.map(&normalize_word/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    :ets.insert(@table, {:vocabulary, words})
    clear_embeddings!()
    :ok
  end

  @doc """
  Loads a newline-separated vocabulary file from disk and sets it as the global vocabulary.
  This also clears any cached embeddings.

  Each line is treated as a word; blank lines are ignored.
  """
  def load_vocabulary_from_file!(path) when is_binary(path) do
    path
    |> File.read!()
    |> String.split(~r/\R/u, trim: true)
    |> set_vocabulary()
  end

  @doc """
  Precomputes and caches embeddings for the current vocabulary.

  Options:
  - :batch_size (default 64) – how many words to embed per batch
  """
  def precompute_embeddings!(opts \\ []) do
    ensure_table!()
    vocab = get_vocabulary()
    batch_size = Keyword.get(opts, :batch_size, 64)

    missing =
      vocab
      |> Enum.reject(&cached_embedding?/1)

    missing
    |> Enum.chunk_every(batch_size)
    |> Enum.each(fn batch ->
      embeddings = GetScore.get_embedding(batch)

      Enum.zip(batch, embeddings)
      |> Enum.each(fn {word, emb} -> put_embedding!(word, emb) end)
    end)

    :ok
  end

  @doc """
  Returns the top-k vocabulary words whose embeddings are closest (by cosine similarity)
  to the synthetic target embedding constructed from `query_word` at desired cosine similarity `s`.

  Options:
  - :top_k (default 1)
  - :candidates – restrict search to a subset of words
  - :exclude_query (default true) – exclude the `query_word` from results if present

  Returns a list of `{word, similarity}` sorted by similarity descending.
  """
  def top_matches_for_desired_similarity(query_word, s, opts \\ []) when is_binary(query_word) do
    ensure_table!()

    top_k = Keyword.get(opts, :top_k, 1)
    exclude_query? = Keyword.get(opts, :exclude_query, true)

    candidates =
      opts[:candidates] ||
        get_vocabulary()

    candidates =
      candidates
      |> Enum.map(&normalize_word/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> then(fn list ->
        if exclude_query?, do: Enum.reject(list, &(&1 == normalize_word(query_word))), else: list
      end)

    # Generate the synthetic target embedding once
    target = GetScore.generate_target_embedding(query_word, s)

    # Get embeddings for candidates (from cache or compute/batch on demand)
    candidate_embeddings = embeddings_for(candidates)

    candidates
    |> Enum.zip(candidate_embeddings)
    |> Enum.map(fn {word, emb} ->
      {word, Nx.to_number(GetScore.cosine_similarity(target, emb))}
    end)
    |> Enum.sort_by(fn {_w, score} -> score end, :desc)
    |> Enum.take(top_k)
  end

  @doc """
  Convenience helper that returns `{best_word, similarity}` or `nil`
  if no candidates are available.
  """
  def best_match_for_desired_similarity(query_word, s, opts \\ []) do
    case top_matches_for_desired_similarity(query_word, s, Keyword.put_new(opts, :top_k, 1)) do
      [{w, sim}] -> {w, sim}
      _ -> nil
    end
  end

  @doc """
  Returns an embedding for a vocabulary word, caching the result.

  If the word is not in the vocabulary, it will still be embedded and cached.
  """
  def embedding_for(word) when is_binary(word) do
    ensure_table!()
    word = normalize_word(word)

    case :ets.lookup(@table, {:emb, word}) do
      [{{:emb, ^word}, emb}] ->
        emb

      _ ->
        [emb] = GetScore.get_embedding([word])
        put_embedding!(word, emb)
        emb
    end
  end

  @doc """
  Returns embeddings for a list of words in the same order, caching any missing entries.

  Performs batched embedding for missing words to leverage the serving's batching.
  Options:
  - :batch_size (default 64)
  """
  def embeddings_for(words, opts \\ []) when is_list(words) do
    ensure_table!()
    batch_size = Keyword.get(opts, :batch_size, 64)

    # Normalize once
    words = Enum.map(words, &normalize_word/1)

    # Split into cached vs missing
    {_cached_pairs, missing_words} =
      Enum.reduce(words, {[], []}, fn w, {cached, missing} ->
        case :ets.lookup(@table, {:emb, w}) do
          [{{:emb, ^w}, emb}] -> {[{w, emb} | cached], missing}
          _ -> {cached, [w | missing]}
        end
      end)

    # Batch-embed the missing words (in stable order)
    missing_words
    |> Enum.reverse()
    |> Enum.chunk_every(batch_size)
    |> Enum.each(fn batch ->
      embeddings = GetScore.get_embedding(batch)

      Enum.zip(batch, embeddings)
      |> Enum.each(fn {w, emb} -> put_embedding!(w, emb) end)
    end)

    # Read all in the same order as requested
    Enum.map(words, fn w ->
      case :ets.lookup(@table, {:emb, w}) do
        [{{:emb, ^w}, emb}] -> emb
        _ -> raise "Embedding not found after caching for word: #{inspect(w)}"
      end
    end)
  end

  # -- Internal helpers --

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :set,
          :named_table,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])

        :ok

      _ ->
        :ok
    end
  end

  defp put_embedding!(word, emb) do
    :ets.insert(@table, {{:emb, word}, emb})
    :ok
  end

  defp cached_embedding?(word) do
    case :ets.lookup(@table, {:emb, normalize_word(word)}) do
      [] -> false
      _ -> true
    end
  end

  defp clear_embeddings! do
    ensure_table!()
    # Delete all entries where key matches {:emb, _}
    :ets.match_delete(@table, {{:emb, :_}, :_})
    :ok
  end

  defp normalize_word(word) when is_binary(word) do
    word
    |> String.trim()
    |> String.downcase()
  end

  # A small default vocabulary. Replace at runtime with `set_vocabulary/1` or a file.
  defp default_vocabulary do
    ~w[
      cat kitten feline dog puppy canine animal pet lion tiger bear wolf fox deer horse sheep goat pig cow chicken duck goose eagle hawk owl shark whale dolphin octopus crab spider insect ant bee butterfly
      car automobile vehicle truck bus train plane boat bike bicycle scooter motorcycle subway tram rocket spaceship ferry yacht sailboat canoe kayak
      computer laptop keyboard mouse monitor screen software hardware code coding program programming developer engineer data database server client api internet web website browser email network protocol cloud storage cache queue algorithm model training inference dataset pipeline
      program programming developer engineer data database server client api library framework package module function process thread task job pipeline
      tree forest leaf branch root flower plant grass garden nature jungle rainforest swamp meadow prairie wood woodland bush shrub seed soil
      water ocean river lake sea stream rain snow ice fire heat burn hot cold warm cool chill thunder lightning rainbow tornado hurricane blizzard fog mist drizzle hail storm weather climate
      sun moon star sky cloud wind storm weather sunrise sunset daylight night midnight dawn dusk
      happy joy glad cheerful smile laugh sad unhappy sorrow cry tear angry afraid scared nervous anxious calm relaxed bored excited surprised tired sleepy hungry thirsty
      king queen prince princess royal throne crown empire kingdom realm leader ruler emperor empress lord lady duke duchess knight noble
      man woman boy girl father mother parent child adult human person people friend family baby kid teen youth elder
      good great excellent fine nice bad poor terrible awful worse worst better best
      fast quick rapid slow speed swift sluggish delay late early ontime punctual timely
      big large huge giant small tiny little minute short long tall high low wide narrow deep shallow thick thin heavy light
      red blue green yellow orange purple pink black white gray brown cyan magenta teal turquoise beige maroon navy violet indigo gold silver bronze
      city town village country nation state capital road street avenue lane highway freeway bridge tunnel port harbor downtown suburb rural urban
      place location area region zone district center middle corner edge border coast shore beach island mountain hill valley desert canyon glacier volcano
      house home apartment room kitchen bathroom bedroom living dining garage window door floor ceiling wall roof table chair sofa bed desk lamp light fan clock phone
      music song melody rhythm harmony sound noise art paint draw picture image photo film movie cinema theater museum gallery dance
      book read write story poem novel paper page letter word sentence paragraph chapter author title library publish print
      food eat drink bread rice meat beef pork chicken fish seafood fruit vegetable sugar salt spice pepper herb oil butter cheese milk egg yogurt cereal chocolate candy cookie cake pie soup salad pizza pasta burger sandwich
      drink beverage coffee tea juice soda water beer wine whiskey vodka rum milkshake cocktail
      school student teacher class lesson study learn education university college campus lecture exam test grade homework
      health medicine hospital clinic doctor nurse pill drug vaccine therapy pain fever cough flu disease virus bacteria injury wound
      sport soccer football baseball basketball tennis golf hockey volleyball rugby cricket swim run walk jump climb lift throw catch kick hit score team coach referee
      clothing shirt pants jeans dress skirt coat jacket hat cap shoe boot sock glove scarf belt sweater hoodie t-shirt
      tools hammer screw screwdriver wrench pliers saw drill nail bolt ladder shovel axe knife tape measure level chisel
      body head face hair eye ear nose mouth tooth teeth tongue hand arm leg foot feet heart brain stomach back skin bone
      finance money bank cash coin credit debit card loan interest tax price cost buy sell trade market stock bond budget income expense pay salary wage bill profit loss
      time date day week month year morning evening night today tomorrow yesterday spring summer autumn winter january february march april may june july august september october november december
      numbers zero one two three four five six seven eight nine ten hundred thousand million billion
      directions north south east west left right up down forward backward inside outside near far
      shapes circle square triangle rectangle line point curve angle edge corner center middle
      verbs be have do say make go know think take see come want use find give tell work call try ask need feel seem leave put keep let begin help talk turn start show hear play move like live believe hold bring happen write provide sit stand lose pay meet include continue set learn change lead understand watch follow stop create speak read allow add spend grow open walk win offer remember love consider appear buy wait serve die send expect build stay fall cut reach kill remain suggest raise pass sell require report decide return explain hope develop carry break receive agree support hit produce eat drink sleep drive ride fly swim
    ]
  end
end
