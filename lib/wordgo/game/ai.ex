defmodule Wordgo.Game.AI do
  @moduledoc """
  Handles AI move logic and strategy for the word game.
  Extracted from GameLive to provide better separation of concerns and testability.
  """

  alias Wordgo.Game
  alias Wordgo.WordToVec.Vocabulary
  alias Phoenix.PubSub

  @doc """
  Determines if an AI move should be executed based on socket state.

  ## Parameters
  - assigns: Socket assigns map

  ## Returns
  {:ok, :should_move} | {:ok, :skip_move}
  """
  def should_make_move?(assigns) do
    cond do
      assigns[:ai_enabled] != true ->
        {:ok, :skip_move}

      assigns.current_turn != "AI" ->
        {:ok, :skip_move}

      true ->
        {:ok, :should_move}
    end
  end

  @doc """
  Executes a complete AI move including position selection, word choice, and board update.

  ## Parameters
  - assigns: Socket assigns map
  - pubsub_module: PubSub module (default: Wordgo.PubSub)

  ## Returns
  {:ok, new_assigns} | {:error, reason}
  """
  def execute_move(assigns, pubsub_module \\ Wordgo.PubSub) do
    board = assigns.board
    size = assigns.board_size
    players = assigns.players || ["AI"]
    ai_difficulty = assigns[:ai_difficulty] || "medium"

    case find_empty_positions(board, size) do
      [] ->
        {:error, :no_empty_positions}

      empty_positions ->
        # Select the best position for AI move
        chosen_coord = select_best_position(board, size, players, ai_difficulty, empty_positions)

        # Choose word based on difficulty and strategy
        word = choose_ai_word(board, chosen_coord, ai_difficulty)

        # Execute the move
        case execute_ai_placement(board, chosen_coord, word, assigns, pubsub_module) do
          {:ok, updated_assigns} -> {:ok, updated_assigns}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Finds all empty positions on the board.
  """
  def find_empty_positions(board, size) do
    occupied =
      board.pieces
      |> Enum.map(&{&1.x, &1.y})
      |> MapSet.new()

    all_coords = for y <- 0..(size - 1), x <- 0..(size - 1), do: {x, y}
    Enum.reject(all_coords, fn coord -> MapSet.member?(occupied, coord) end)
  end

  @doc """
  Selects the best position for AI move based on difficulty and strategy.
  """
  def select_best_position(board, size, players, ai_difficulty, empty_positions) do
    difficulty_params = get_difficulty_params(ai_difficulty)
    target_opponent = find_target_opponent(players)

    frontier_coords =
      analyze_frontier_positions(
        board,
        size,
        target_opponent,
        empty_positions,
        difficulty_params
      )

    case frontier_coords do
      [{coord, _score, _b, _g} | _] ->
        coord

      _ ->
        # Fallback to growth strategy or random
        select_growth_position(board, size, empty_positions)
    end
  end

  @doc """
  Chooses an AI word based on difficulty level and existing pieces.
  """
  def choose_ai_word(board, {x, y}, ai_difficulty) do
    ai_words = Game.get_player_words(board, "AI")
    target_similarity = get_target_similarity(ai_difficulty)

    # Get all words currently on the board (case-insensitive)
    existing_words =
      board.pieces
      |> Enum.map(&String.downcase(&1.word))

    case ai_words do
      [] ->
        # First move: random vocabulary word, but ensure uniqueness
        vocab = Vocabulary.get_vocabulary()
        unique_vocab = vocab |> Enum.reject(&(String.downcase(&1) in existing_words))

        if unique_vocab == [] do
          nil
        else
          Enum.random(unique_vocab)
        end

      _ ->
        choose_strategic_word(board, {x, y}, ai_words, target_similarity, existing_words)
    end
  end

  # Private functions

  defp get_difficulty_params(ai_difficulty) do
    case String.downcase(to_string(ai_difficulty)) do
      "easy" -> %{target_sim: 0.3, block_weight: 1, grow_weight: 1}
      "hard" -> %{target_sim: 0.85, block_weight: 3, grow_weight: 1}
      # medium
      _ -> %{target_sim: 0.6, block_weight: 2, grow_weight: 1}
    end
  end

  defp get_target_similarity(ai_difficulty) do
    case String.downcase(to_string(ai_difficulty)) do
      "easy" -> 0.3
      "hard" -> 0.85
      # medium
      _ -> 0.6
    end
  end

  defp find_target_opponent(players) do
    case next_player(players, "AI") do
      "AI" -> Enum.find(players, fn n -> n != "AI" end)
      other -> other
    end
  end

  defp next_player(players, current) do
    case Enum.find_index(players, &(&1 == current)) do
      nil -> List.first(players)
      index -> Enum.at(players, rem(index + 1, length(players)))
    end
  end

  defp get_neighbors({x, y}, size) do
    [{x + 1, y}, {x - 1, y}, {x, y + 1}, {x, y - 1}]
    |> Enum.filter(fn {nx, ny} -> nx >= 0 and ny >= 0 and nx < size and ny < size end)
  end

  defp analyze_frontier_positions(
         board,
         size,
         target_opponent,
         empty_positions,
         difficulty_params
       ) do
    if target_opponent do
      empty_set = MapSet.new(empty_positions)
      ai_piece_coords = get_ai_piece_coords(board)

      groups = Game.get_player_groups(board, target_opponent)
      largest_group = find_largest_group(groups)

      analyze_positions_against_group(
        largest_group,
        empty_set,
        ai_piece_coords,
        size,
        difficulty_params
      )
    else
      []
    end
  end

  defp get_ai_piece_coords(board) do
    board.pieces
    |> Enum.filter(&(&1.player == "AI"))
    |> Enum.map(&{&1.x, &1.y})
    |> MapSet.new()
  end

  defp find_largest_group(groups) do
    case groups do
      [] -> []
      _ -> Enum.max_by(groups, &length/1, fn -> [] end)
    end
  end

  defp analyze_positions_against_group(
         largest_group,
         empty_set,
         ai_piece_coords,
         size,
         difficulty_params
       ) do
    largest_group
    |> Enum.flat_map(fn p -> get_neighbors({p.x, p.y}, size) end)
    |> Enum.filter(&MapSet.member?(empty_set, &1))
    |> Enum.uniq()
    |> Enum.map(fn coord ->
      score_position(coord, largest_group, empty_set, ai_piece_coords, size, difficulty_params)
    end)
    |> Enum.sort_by(
      fn {_c, score, block_adj, grow_adj} -> {score, block_adj, grow_adj} end,
      :desc
    )
  end

  defp score_position(coord, largest_group, empty_set, ai_piece_coords, size, difficulty_params) do
    block_adj = count_blocking_adjacency(coord, largest_group, size)
    grow_adj = count_growth_adjacency(coord, ai_piece_coords, size)

    # 2-step lookahead
    empty_after = MapSet.delete(empty_set, coord)
    opp_next_best = calculate_opponent_next_best(largest_group, empty_after, size)
    ai_future = calculate_ai_future_growth(coord, empty_after, size)

    %{block_weight: block_w, grow_weight: grow_w} = difficulty_params

    final_score =
      block_w * block_adj +
        grow_w * grow_adj +
        div(grow_w * ai_future, 2) -
        opp_next_best

    {coord, final_score, block_adj, grow_adj}
  end

  defp count_blocking_adjacency(coord, largest_group, size) do
    get_neighbors(coord, size)
    |> Enum.count(fn c ->
      Enum.any?(largest_group, fn p -> {p.x, p.y} == c end)
    end)
  end

  defp count_growth_adjacency(coord, ai_piece_coords, size) do
    get_neighbors(coord, size)
    |> Enum.count(fn c -> MapSet.member?(ai_piece_coords, c) end)
  end

  defp calculate_opponent_next_best(largest_group, empty_after, size) do
    largest_group
    |> Enum.flat_map(fn p -> get_neighbors({p.x, p.y}, size) end)
    |> Enum.filter(&MapSet.member?(empty_after, &1))
    |> Enum.map(fn c2 ->
      get_neighbors(c2, size)
      |> Enum.count(fn c3 ->
        Enum.any?(largest_group, fn p -> {p.x, p.y} == c3 end)
      end)
    end)
    |> Enum.max(fn -> 0 end)
  end

  defp calculate_ai_future_growth(coord, empty_after, size) do
    get_neighbors(coord, size)
    |> Enum.count(&MapSet.member?(empty_after, &1))
  end

  defp select_growth_position(board, size, empty_positions) do
    ai_piece_coords = get_ai_piece_coords(board)

    grow_candidates =
      empty_positions
      |> Enum.map(fn coord ->
        adj = count_growth_adjacency(coord, ai_piece_coords, size)
        {coord, adj}
      end)
      |> Enum.sort_by(fn {_c, adj} -> adj end, :desc)

    case grow_candidates do
      [{coord, _} | _] -> coord
      _ -> Enum.random(empty_positions)
    end
  end

  defp choose_strategic_word(board, {x, y}, ai_words, target_similarity, existing_words) do
    ai_groups = Game.get_player_groups(board, "AI")

    {nearest_group, _dist} = find_nearest_group(ai_groups, {x, y})

    base_candidates =
      case nearest_group do
        [] -> ai_words
        grp -> Enum.map(grp, & &1.word)
      end

    base = Enum.random(base_candidates)

    # Try to get top 5 matches for similarity, filter for uniqueness
    candidates =
      Vocabulary.top_matches_for_desired_similarity(base, target_similarity, top_k: 5)
      |> Enum.map(fn {w, _sim} -> w end)
      |> Enum.reject(&(String.downcase(&1) in existing_words))

    # If no unique candidates, fallback to unique vocab
    word =
      case candidates do
        [unique | _] ->
          unique

        [] ->
          vocab = Vocabulary.get_vocabulary()
          unique_vocab = vocab |> Enum.reject(&(String.downcase(&1) in existing_words))

          if unique_vocab == [] do
            nil
          else
            Enum.random(unique_vocab)
          end
      end

    word
  end

  defp find_nearest_group(ai_groups, {x, y}) do
    ai_groups
    |> Enum.map(fn grp ->
      min_dist =
        grp
        |> Enum.map(fn p -> abs(p.x - x) + abs(p.y - y) end)
        |> Enum.min(fn -> 999_999 end)

      {grp, min_dist}
    end)
    |> Enum.min_by(fn {_g, d} -> d end, fn -> {[], 999_999} end)
  end

  defp execute_ai_placement(board, {x, y}, word, assigns, pubsub_module) do
    # If word is nil, cannot place
    if is_nil(word) or word == "" do
      {:error, :no_unique_word_available}
    else
      case Game.place_word(board, {x, y}, word, "AI") do
        {:ok, updated_board} ->
          players = assigns.players || ["AI"]
          next_turn = next_player(players, "AI")

          # Broadcast move
          PubSub.broadcast(
            pubsub_module,
            assigns.topic,
            {:move, %{board: updated_board, next_turn: next_turn}}
          )

          # Update local assigns
          current_name = assigns.current_player.name
          word_groups = Game.get_player_groups(updated_board, current_name)
          group_scores = Game.get_player_groups_with_scores(updated_board, current_name)

          updated_assigns =
            Map.merge(assigns, %{
              board: updated_board,
              current_turn: next_turn,
              selected_position: nil,
              current_word: "",
              error_message: nil,
              word_groups: word_groups,
              group_scores: group_scores
            })

          {:ok, updated_assigns}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
